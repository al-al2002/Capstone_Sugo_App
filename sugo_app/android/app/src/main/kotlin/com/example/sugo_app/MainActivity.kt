package com.example.sugo_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createUrgentChannel()
    }

    /**
     * The channel urgent job requests arrive on (2026-11-17): the "hard
     * notify" the user asked for. Full importance, so it sounds, vibrates and
     * drops down over whatever is on screen, and it shows on the lock screen.
     *
     * The server sends urgent pushes with `channel_id = "sugo_urgent"`
     * (supabase/functions/_shared/fcm.ts). On Android 8+ a push for a channel
     * the app never created falls back to the default one - quiet - so it has
     * to exist before the first urgent request arrives. Creating a channel
     * that already exists is a no-op, so this is safe on every launch.
     */
    private fun createUrgentChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            "sugo_urgent",
            "Urgent job requests",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "A client needs you today. You have 5 minutes to accept."
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 600, 250, 600, 250, 600)
            enableLights(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(channel)
    }
}
