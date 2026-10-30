# Nightwell Chat

Independent **black-and-white** messenger by Nightwell. Native iPhone UI (SwiftUI) and Python/FastAPI backend.

## What works in v0.1

- Register/login with salted scrypt password hashes, expiring JWT sessions, token in iOS Keychain.
- User search by username or display name; one-to-one and group chats.
- SQLite persistence, timeline pagination, unread counts and read markers.
- Real-time WebSocket delivery (with reconnect), message editing/deletion, emoji reactions and replies.
- Native dark monochrome iOS UI with frosted glass panels.
- Tests for authentication, permissions, chats and live events; GitHub Actions iOS Simulator build.

**This is an MVP, not a production Telegram equivalent.** No end-to-end encryption, push notifications, images/files, voice/video calls, spam protection, moderation tooling, account recovery or multi-worker WebSocket fan-out yet. Do not use it for sensitive conversations.

## Start backend on Windows (NO Docker)

1. Install **Python 3.12 (recommended)** from [python.org](https://www.python.org/downloads/). Supported by this Windows launcher: Python 3.10–3.13. Do not use Python 3.15 for this initial Windows build.
2. Download or clone this repository and double-click **`Start_Nightwell_Chat.bat`**.
3. The launcher automatically selects a supported Python interpreter, creates a private `.venv`, installs Python dependencies and starts the server. If an old `.venv` was created with Python 3.14/3.15, it is replaced automatically. **Your `.env` and `data` directory are not deleted.**
4. The first run also creates `.env` with a strong random `SECRET_KEY` and the `data/nightwell_chat.db` SQLite database. **Keep `.env` secret and back up the `data` directory.** Never delete `.env` when upgrading or existing sessions will stop working.
5. Open **http://127.0.0.1:8009/health** in your browser. It should return `{"ok":true,"service":"nightwell-chat"}`.
6. To stop the local server, use **`Stop_Nightwell_Chat.bat`**, or press Ctrl+C in the server window.

### Fixing `Failed building wheel for pyyaml` on Windows

Older versions of the launcher used `py -3`, which picked the newest installed Python. On machines with Python 3.15 this could cause a failed PyYAML build asking for Microsoft Visual C++ 14.0. The launcher now verifies that the interpreter actually executes Python code before selecting it (rather than relying on a misleading exit code). It prefers 3.12, then 3.13/3.11/3.10. If none of these versions is installed, run `py install 3.12` (or `winget install -e --id Python.Python.3.12`) and restart the BAT. It replaces only an incompatible `.venv` and installs a smaller Uvicorn dependency set without PyYAML. The app still supports WebSockets.

If you have **only Python 3.15**, install Python 3.12 first. One Windows option is `winget install -e --id Python.Python.3.12` or use the [official download](https://www.python.org/downloads/). Then close the old terminal, extract the new project ZIP over the old files (without deleting `.env` or `data`), and run `Start_Nightwell_Chat.bat`. If you cannot replace the whole folder, copy `Start_Nightwell_Chat.bat` and `server/requirements.txt` from the new archive. You do **not** need Visual Studio Build Tools for this fix.

The application listens **only on 127.0.0.1:8009**. You do **not** need to open this port in your router. To make iPhone clients connect over the internet, point `chat.nightwell.fun` at your server and add the following to your existing Caddy configuration:

```caddy
chat.nightwell.fun {
    reverse_proxy 127.0.0.1:8009
}
```

Caddy handles HTTPS and WebSockets and can coexist with Nightwell Music on the same host. Forward **80/443 to Caddy**, not 8009. The iPhone app initially uses `https://chat.nightwell.fun` (modifiable in the app's Settings). The hostname is not automatically configured by this repository.

### Optional: Docker deployment

If you prefer Docker, copy `.env.example` to `.env`, replace the placeholder `SECRET_KEY` with a random value from `python -c "import secrets; print(secrets.token_urlsafe(48))"`, and run `docker compose up -d --build`. The Docker deployment uses its **own volume**; it does not share the non-Docker `data` directory automatically. To stop Docker deployment, run `docker compose down`.

Neither deployment requires changes to the existing Nightwell Music server.

## iOS

1. In the `ios` folder run `xcodegen generate` on macOS (XcodeGen is installed with `brew install xcodegen`).
2. Open `NightwellChat.xcodeproj` in Xcode, select your Apple developer team and update bundle ID if needed.
3. Build or run on your iPhone, or archive and distribute with a valid Apple signing identity and provisioning profile.
4. Initial server address: `https://chat.nightwell.fun`; change it from **Settings** if using your own TLS hostname.

GitHub Actions builds both an unsigned Simulator `.app` and an **unsigned device `.ipa`**. The unsigned IPA requires valid Apple signing before installation on a physical iPhone. No signing credentials are stored in this repository.

## Local tests

```sh
cd server
pip install -r requirements.txt
SECRET_KEY=some-random-string-longer-than-32-characters python -m pytest -q
```

## Production security and scaling checklist

Add IP/user rate limiting on login and registration, abuse reporting and moderation, email or passkey recovery, stronger session revocation, object storage for attachments, PostgreSQL and Redis fan-out before broad public launch. Terminate TLS at a proxy, restrict trusted forwarded headers and implement HTTPS monitoring. SQLite and one worker are intentionally chosen for the initial small private trial.

## Phone sign-in and contacts (no SMS)

- `POST /auth/phone/register` registers a new account with a phone number and password. `POST /auth/phone/login` signs in. Phone numbers are normalized to E.164 format; Russian 8XXXXXXXXXX, 7XXXXXXXXXX and ten-digit mobile 9XXXXXXXXX also work. Phone numbers are unique. Passwords are salted and hashed with scrypt, with persisted rate limits for phone login.
- **Important:** Without SMS/call or another out-of-band check, only the **format** of a phone number can be validated. The app cannot determine whether the person owns the number. There is no password recovery by phone. Do not treat this as phone-number verification.
- Existing username/password accounts retain their identity, chats and history. Sign in with the legacy option, then link a phone number from Settings using the account's current password. Do not register a new account if you need old chats.
- Contacts are read on the device only after granting access. The device sends only a selected phone number to `/users/by-phone`, not the whole contact list. The match requires an exact number, the other person's opt-in and an authenticated session.
- Phone search is **off by default**, must be explicitly enabled by each user and is rate limited. Because phone ownership is unverified, a match is a user-entered claim, not a verified identity.
- No SMS provider, SMS secret or SMS charge is required. For public deployment add abuse protection, account recovery and real phone ownership verification before making claims about verified contacts.

## Android 0.3

- Native Android client (Java, minimum Android 8.0) in `android/`, dark monochrome UI.
- Phone + password registration/login, username/password migration login, encrypted session token using Android Keystore.
- Chat list, private and group messages, realtime WebSocket refresh, send/edit/delete/reactions, user search and selected-number contact lookup.
- Requests `READ_CONTACTS` only when opening the Contacts screen; address book is read locally, no batch upload. Only a tapped number is queried against `/users/by-phone`, which respects the other person's opt-in privacy setting.
- Profile, phone linking, opt-in discovery, HTTPS server setting and logout.
- GitHub Actions `.github/workflows/android.yml` compiles a **debug-signed APK** (Android permits installing this build for testing; not suitable for Play Store release). Build: `cd android && gradle :app:assembleDebug` using Gradle 8.10.2, Android SDK 35 and JDK 17.

**No SMS:** phone numbers have a syntax check only. Any user can claim an unverified number. Phone discovery is off by default; do not rely on it as proof of identity. The app does not support push notifications, media uploads, voice/video calls, E2EE or recovery of a lost password. For public launch, implement number-ownership verification, abuse prevention, credential recovery and a security assessment.

For existing servers, replace only the server code/files and restart `Start_Nightwell_Chat.bat`; the `setup()` migration adds columns and tables without deleting chats. **Back up** `.env` and `data/nightwell_chat.db` first. The same API powers iOS and Android. Nightwell Music/Caddy are separate and should remain unchanged.
