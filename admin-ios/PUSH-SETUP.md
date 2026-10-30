# Nightwell Admin notifications

## What is implemented

- On-device warnings if a service that was previously reachable becomes unavailable.
- Windows bridge monitors local Music port 8080 and Chat port 8009 every 25 seconds, confirms outage after 2 failures, and notifies on recovery.
- One warning after 3 slow checks (default over 1800 ms); one recovery message after 2 normal checks.
- Authenticated event history persisted in SQLite (up to 800 events).
- Administration action results (restart/stop/start/update, backup, errors) published as events.
- Optional APNs push for a signed iPhone app when the app is closed. No secret embedded into the IPA.

## Windows setup (once)

Copy the complete "admin-bridge" folder to C:\Nightwell Admin and run Start_Nightwell_Admin.bat.
Existing admin-token.txt and config.json should be kept (NEVER replace or upload them).

The bridge listens at **127.0.0.1:8011**. Do NOT expose it directly on a public HTTP port.
Connect through private VPN or an HTTPS reverse proxy with further access controls.

Background APNs needs (Apple Developer account):
- Push Notifications enabled for App ID fun.nightwell.admin.
- The IPA signed with an Apple development/distribution provisioning profile granting aps-environment.
- An APNs auth key downloaded from Apple Developer. Keep its *.p8 file OUTSIDE GitHub, e.g. C:\Nightwell Admin\secrets\AuthKey_ABCD123456.p8.
- On Windows, Python 3.12 and these dependencies:
  py -3.12 -m pip install "httpx[http2]" "PyJWT[crypto]"
- Configure environment variables for the process before launch:
  NIGHTWELL_APNS_TEAM_ID
  NIGHTWELL_APNS_KEY_ID
  NIGHTWELL_APNS_KEY_FILE
  NIGHTWELL_APNS_ENV=production  (or sandbox for a development-signed app)
- Set NIGHTWELL_MONITOR_INTERVAL=25 and NIGHTWELL_SLOW_MS=1800 to customize monitoring (optional).

The **unsigned** GitHub IPA includes project configuration for the push entitlement, but signing it with a certificate/profile that lacks Push Notifications will NOT make APNs work.

In the iPhone app, open Settings -> Notifications, grant iOS permission and enable push. Connect to your HTTPS bridge using the admin token. Use "Send test" to verify.

If the bridge process stops or the Windows PC loses network access, that same PC cannot send push. A second external uptime monitor is required to alert when the entire computer is offline.

Don't commit APNs keys, admin-token.txt, databases, .env files or credentials to GitHub. APNs device tokens are stored in the local bridge SQLite database; no other user data is required.
