"""Native Android FCM and iPhone Web Push API smoke checks."""
from fastapi.testclient import TestClient
from app import app, db
from test_api import auth, headers


def test_web_client_and_push_registration():
    with TestClient(app) as c:
        assert c.get("/").status_code == 200
        assert "Nightwell Chat" in c.get("/").text
        assert c.get("/sw.js").status_code == 200
        assert c.get("/manifest.webmanifest").status_code == 200
        assert c.get("/chat-web.js").status_code == 200
        assert c.post("/push/fcm/register",json={"token":"x"*100}).status_code == 401
        a=auth(c,"pushusera");b=auth(c,"pushuserb")
        good={"token":"a"*100}
        assert c.post("/push/fcm/register",headers=headers(a),json=good).json()["ok"]
        assert c.post("/push/fcm/register",headers=headers(b),json=good).status_code == 200
        with db() as con:
            row=con.execute("SELECT user_id,kind FROM push_devices").fetchone()
            assert row["user_id"] == b["user"]["id"] and row["kind"]=="fcm"
        assert c.request("DELETE","/push/fcm/unregister",headers=headers(a),json=good).status_code==200
        with db() as con:
            assert con.execute("SELECT COUNT(*) FROM push_devices").fetchone()[0]==1
        assert c.request("DELETE","/push/fcm/unregister",headers=headers(b),json=good).status_code==200
        with db() as con:
            assert con.execute("SELECT COUNT(*) FROM push_devices").fetchone()[0]==0


def test_web_endpoint_ssrf_protection_and_unregister():
    with TestClient(app) as c:
        a=auth(c,"pushwebuser")
        invalid={"endpoint":"https://private.example.net/notify",
                 "keys":{"p256dh":"p"*80,"auth":"a"*25}}
        assert c.post("/push/web/register",headers=headers(a),json=invalid).status_code==422
        valid={**invalid,"endpoint":"https://web.push.apple.com/QZw123"}
        assert c.post("/push/web/register",headers=headers(a),json=valid).status_code==200
        state=c.get("/push/status",headers=headers(a)).json()
        assert state["devices"]["web"]==1
        assert c.delete("/push/web/unregister",headers=headers(a)).status_code==200
        assert "web" not in c.get("/push/status",headers=headers(a)).json()["devices"]
