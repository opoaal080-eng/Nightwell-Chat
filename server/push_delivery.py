"""Platform push delivery for Nightwell Chat. Keys stay on the server.

Supports:
 * Firebase Cloud Messaging for the native Android APK
 * Standards-based Web Push for the iPhone Home Screen web app
Never expose FCM service credentials or VAPID private keys through an API.
"""
from __future__ import annotations

import base64
import hashlib
import json
import logging
import os
from pathlib import Path

log = logging.getLogger("nightwell.push")


def token_hash(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def ensure_vapid(data_dir: Path) -> tuple[str, str] | None:
    """Create a persistent VAPID key pair once, only if contact is configured."""
    if not os.getenv("WEBPUSH_CONTACT", "").startswith("mailto:"):
        return None
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec

    data_dir.mkdir(parents=True, exist_ok=True)
    private_path = data_dir / "webpush-vapid-private.pem"
    public_path = data_dir / "webpush-vapid-public.txt"
    if not private_path.exists():
        private_key = ec.generate_private_key(ec.SECP256R1())
        encoded = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
        try:
            with private_path.open("xb") as f:
                f.write(encoded)
        except FileExistsError:
            pass
    key = serialization.load_pem_private_key(private_path.read_bytes(), password=None)
    if not isinstance(key, ec.EllipticCurvePrivateKey):
        raise RuntimeError("VAPID key is invalid")
    pub = key.public_key().public_numbers()
    raw = b"\x04" + pub.x.to_bytes(32, "big") + pub.y.to_bytes(32, "big")
    public = base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")
    if not public_path.exists() or public_path.read_text(encoding="ascii") != public:
        public_path.write_text(public, encoding="ascii")
    return str(private_path), public


def firebase_ready() -> bool:
    credentials_path = os.getenv("FIREBASE_CREDENTIALS", "").strip()
    if not credentials_path or not Path(credentials_path).is_file():
        return False
    try:
        import firebase_admin
        from firebase_admin import credentials
        if not firebase_admin._apps:
            firebase_admin.initialize_app(credentials.Certificate(credentials_path))
        return True
    except Exception:
        log.exception("FCM initialization failed")
        return False


def deliver_fcm(registration_token: str, payload: dict) -> bool:
    if not firebase_ready():
        return False
    from firebase_admin import messaging
    try:
        kind = str(payload.get("type", "message"))
        notification = messaging.Notification(title=str(payload.get("title", "Nightwell Chat")),
                                               body=str(payload.get("body", "Новое событие")))
        result = messaging.Message(
            token=registration_token,
            notification=notification,
            data={key: str(val) for key, val in payload.items()},
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    channel_id="calls" if kind == "incoming_call" else "messages",
                    sound="default",
                ),
            ),
        )
        messaging.send(result)
        return True
    except Exception:
        log.exception("FCM delivery failed")
        return False


def deliver_web(subscription: dict, payload: dict, vapid_key: str) -> bool:
    from pywebpush import WebPushException, webpush
    try:
        webpush(
            subscription_info=subscription,
            data=json.dumps(payload, ensure_ascii=False),
            vapid_private_key=vapid_key,
            vapid_claims={"sub": os.environ["WEBPUSH_CONTACT"]},
            ttl=60 if payload.get("type") == "incoming_call" else 3600,
        )
        return True
    except WebPushException as exc:
        log.warning("Web push failed (HTTP status %s)",
                    getattr(getattr(exc, "response", None), "status_code", "unknown"))
        return False
    except Exception:
        log.exception("Web push failed")
        return False


def deliver_many(entries: list[dict], payload: dict, base_dir: Path) -> None:
    """Called from a background thread, without blocking chat API response."""
    vapid = None
    for entry in entries:
        try:
            if entry["kind"] == "fcm":
                deliver_fcm(entry["token"], payload)
            elif entry["kind"] == "web":
                if vapid is None:
                    vapid = ensure_vapid(base_dir)
                if vapid:
                    deliver_web(json.loads(entry["token"]), payload, vapid[0])
        except Exception:
            log.exception("Push for device failed")
