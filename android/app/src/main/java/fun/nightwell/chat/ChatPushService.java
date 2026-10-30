package fun.nightwell.chat;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.content.pm.PackageManager;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import com.google.firebase.FirebaseApp;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;
import org.json.JSONObject;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Map;

/** System notifications for Nightwell Chat. FCM works when the APK is closed.
 * Requires android/app/google-services.json from a Firebase project.
 */
public final class ChatPushService extends FirebaseMessagingService {
    public static final String MESSAGES = "messages";
    public static final String CALLS = "calls";

    static void makeChannels(Context context) {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationManager manager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        NotificationChannel messages = new NotificationChannel(MESSAGES, "Сообщения Nightwell",
                NotificationManager.IMPORTANCE_HIGH);
        messages.setDescription("Личные и групповые сообщения, фотографии и файлы");
        messages.enableVibration(true);
        manager.createNotificationChannel(messages);
        NotificationChannel calls = new NotificationChannel(CALLS, "Входящие звонки",
                NotificationManager.IMPORTANCE_HIGH);
        calls.setDescription("Входящие звонки Nightwell Chat");
        calls.enableVibration(true);
        calls.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
        manager.createNotificationChannel(calls);
    }

    static void refreshToken(Context context) {
        if (context.getSharedPreferences("MainActivity", MODE_PRIVATE)
                .getString("accessToken", "").isEmpty()) return;
        try {
            if (FirebaseApp.getApps(context).isEmpty()) return;
            FirebaseMessaging.getInstance().getToken().addOnSuccessListener(token ->
                transmitToken(context.getApplicationContext(), token, "POST"))
                .addOnFailureListener(err ->
                    android.util.Log.w("NightwellChat", "FCM token unavailable", err));
        } catch (RuntimeException exc) {
            android.util.Log.w("NightwellChat", "Firebase is not configured", exc);
        }
    }

    static void unregister(Context context) {
        try {
            if (FirebaseApp.getApps(context).isEmpty()) return;
            FirebaseMessaging.getInstance().getToken().addOnSuccessListener(token ->
                transmitToken(context.getApplicationContext(), token, "DELETE"));
        } catch (RuntimeException ignored) {}
    }

    private static void transmitToken(Context context, String fcmToken, String method) {
        final String account = context.getSharedPreferences("MainActivity", MODE_PRIVATE)
                .getString("accessToken", "");
        if (account.isEmpty() || fcmToken == null || fcmToken.isEmpty()) return;
        new Thread(() -> {
            HttpURLConnection conn = null;
            try {
                conn = (HttpURLConnection) new URL(MainActivity.HOST +
                    (method.equals("DELETE") ? "/push/fcm/unregister" : "/push/fcm/register")).openConnection();
                conn.setRequestMethod(method);
                conn.setConnectTimeout(10000);
                conn.setReadTimeout(10000);
                conn.setRequestProperty("Authorization", "Bearer " + account);
                conn.setRequestProperty("Content-Type", "application/json");
                conn.setDoOutput(true);
                byte[] bytes = new JSONObject().put("token", fcmToken).toString()
                        .getBytes(StandardCharsets.UTF_8);
                try (OutputStream stream = conn.getOutputStream()) { stream.write(bytes); }
                int code = conn.getResponseCode();
                if (code != 200) android.util.Log.w("NightwellChat", "FCM registration HTTP " + code);
            } catch (Exception exc) {
                android.util.Log.w("NightwellChat", "FCM server registration failed", exc);
            } finally {
                if (conn != null) conn.disconnect();
            }
        }, "NightwellFCMRegistration").start();
    }

    @Override public void onNewToken(String token) {
        super.onNewToken(token);
        transmitToken(getApplicationContext(), token, "POST");
    }

    @Override public void onMessageReceived(RemoteMessage message) {
        makeChannels(this);
        Map<String,String> data=message.getData();
        String kind=data.getOrDefault("type","message");
        boolean call="incoming_call".equals(kind);
        String title=data.getOrDefault("title",call?"Входящий звонок":"Nightwell Chat");
        String body=data.getOrDefault("body","Новое сообщение");
        // Firebase auto-displays the notification when the app is backgrounded
        // if an FCM notification payload is present. This method handles foreground delivery.
        if (message.getNotification()!=null) {
            if (title.equals(call?"Входящий звонок":"Nightwell Chat"))
                title=message.getNotification().getTitle();
            if (body.equals("Новое сообщение"))body=message.getNotification().getBody();
        }
        if (Build.VERSION.SDK_INT>=33 &&
              checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)
            return;
        Intent intent=new Intent(this,MainActivity.class)
            .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TOP);
        String chatId=data.get("chat_id");
        if(chatId!=null)intent.putExtra("chat_id",chatId);
        PendingIntent pending=PendingIntent.getActivity(this,
            (int)(System.currentTimeMillis()&0x7fffffff),intent,
            PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        NotificationCompat.Builder notification = new NotificationCompat.Builder(this,call?CALLS:MESSAGES)
            .setSmallIcon(android.R.drawable.ic_dialog_email)
            .setContentTitle(title == null ? "Nightwell Chat" : title)
            .setContentText(body == null ? "Новое сообщение" : body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(call?NotificationCompat.CATEGORY_CALL:NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE);
        NotificationManagerCompat.from(this).notify(
            (int)(System.currentTimeMillis()&0x7fffffff),notification.build());
    }
}
