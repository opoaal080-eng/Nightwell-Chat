package fun.nightwell.chat;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;

/**
 * Foreground microphone call lifetime, started only while CallActivity is visible
 * and RECORD_AUDIO permission has already been granted.
 * The WebRTC transport remains owned by the live CallActivity WebView.
 */
public final class CallForegroundService extends Service {
    static final String CHANNEL = "active_calls";
    private PowerManager.WakeLock wakeLock;

    static void begin(Context context) {
        Intent intent = new Intent(context, CallForegroundService.class);
        try {
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent);
            else context.startService(intent);
        } catch (RuntimeException e) {
            android.util.Log.w("NightwellCall", "Cannot start foreground microphone service", e);
        }
    }

    static void finish(Context context) {
        try { context.stopService(new Intent(context, CallForegroundService.class)); }
        catch (RuntimeException ignored) {}
    }

    @Override public void onCreate() {
        super.onCreate();
        NotificationManager manager =
            (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        NotificationChannel channel = new NotificationChannel(
            CHANNEL, "Активный звонок", NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("Продолжающийся голосовой звонок Nightwell Chat");
        channel.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
        manager.createNotificationChannel(channel);
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        Intent open = new Intent(this, CallActivity.class)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pending = PendingIntent.getActivity(this, 8021, open,
            PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification notification = new Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle("Nightwell Chat")
            .setContentText("Идёт голосовой звонок · нажми, чтобы вернуться")
            .setContentIntent(pending)
            .setCategory(Notification.CATEGORY_CALL)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .build();
        try {
            if (Build.VERSION.SDK_INT >= 29)
                startForeground(8021, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE);
            else startForeground(8021, notification);
            PowerManager power = (PowerManager) getSystemService(POWER_SERVICE);
            if (power != null && wakeLock == null) {
                wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "NightwellChat:Call");
                wakeLock.acquire();
            }
        } catch (RuntimeException e) {
            android.util.Log.e("NightwellCall", "Foreground call failed to start", e);
            stopSelf();
            return START_NOT_STICKY;
        }
        return START_NOT_STICKY;
    }

    @Override public void onDestroy() {
        if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        wakeLock = null;
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent) { return null; }
}
