# Nightwell Chat notifications · v0.8.0

## Android APK: native system notifications (not Web Push)

Android uses Firebase Cloud Messaging (FCM). Android 13+ asks for POST_NOTIFICATIONS
and there are separate notification channels for messages and calls.

**The Firebase project is not included and cannot be created automatically from GitHub.**
1. At https://console.firebase.google.com create a free Firebase project.
2. Add Android app with package name fun.nightwell.chat.
3. Download google-services.json. For GitHub Actions builds, open repository
   Settings -> Secrets and variables -> Actions and create a repository secret
   NIGHTWELL_FIREBASE_ANDROID_JSON with the complete JSON file content.
   On a trusted local build machine, place it in android/app/google-services.json.
4. Build again. Without that file the APK still builds, but background FCM
   notifications cannot work.
5. In Firebase project settings -> Service accounts generate the private service
   account JSON. Put it OUTSIDE the GitHub repository on your Windows server,
   for example C:\Nightwell Chat\secrets\firebase-admin.json.
6. Add to your existing Nightwell Chat .env:
   FIREBASE_CREDENTIALS=C:\Nightwell Chat\secrets\firebase-admin.json
7. Restart Chat. On Android, grant notifications and log in to register its
   device token on the server. The device token unregisters on logout.

Do not upload the private service-account JSON to GitHub or ChatGPT.

## iPhone Web Push (without paid Apple Developer account)

1. Update the Nightwell Chat Windows server, preserve old .env, data, DB and media.
2. Add WEBPUSH_CONTACT=mailto:YOUR_REAL_EMAIL to private .env.
3. Restart Chat. VAPID keys are created once inside the private data folder.
4. In Safari open https://chat.nightwell.fun and Add to Home Screen.
5. Launch the installed Home Screen web app, log in, tap Enable notifications,
   and allow notifications. iOS 16.4+ supports this.
6. The installed web app receives Web Push when closed.

Web Push does NOT make the existing unsigned native iOS IPA receive push.
Its icon and notifications belong to the installed web app.

## Server behavior

- Send notifications for text, files/photos, and incoming call invitations.
- Do not notify the message sender.
- Device registration is authenticated, capped per user, and transferred
  to the most recent logged-in account.
- Push HTTP delivery is asynchronous and doesn't slow down chat sending.
- No keys or secrets are committed to GitHub.
- The old database is migrated without removing existing accounts or chats.

The updated Windows backend must be installed manually. GitHub commits
do not automatically update your home server.
