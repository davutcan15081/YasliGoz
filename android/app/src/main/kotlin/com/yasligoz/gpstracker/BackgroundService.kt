package com.yasligoz.gpstracker

import android.app.*
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import android.app.NotificationManager
import android.app.NotificationChannel
import android.content.Context
import android.util.Log
import android.os.PowerManager
import android.os.PowerManager.WakeLock

class BackgroundService : Service() {
    private var flutterEngine: FlutterEngine? = null
    private var methodChannel: MethodChannel? = null
    private var wakeLock: WakeLock? = null
    private val CHANNEL_ID = "background_service_channel"
    private val NOTIFICATION_ID = 1001

    override fun onCreate() {
        super.onCreate()
        Log.d("BackgroundService", "Servis oluşturuldu")
        
        // Wake lock al
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "GpsTracker::BackgroundServiceWakeLock"
        )
        wakeLock?.acquire(10*60*1000L) // 10 dakika
        
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
        
        // Flutter engine'i başlat
        startFlutterEngine()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(NotificationManager::class.java)
            
            // Eğer kanal zaten varsa sil
            notificationManager.deleteNotificationChannel(CHANNEL_ID)
            
            val channel = NotificationChannel(
                CHANNEL_ID,
                "GPS Tracker Arka Plan Servisi",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Yaşlı takip sistemi arka plan servisi"
                setShowBadge(true)
                enableLights(true)
                enableVibration(false)
                setSound(null, null)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Ortam Sesi Dinleniyor")
            .setContentText("Yaşlı cihazında ortam sesi arka planda dinleniyor")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    private fun startFlutterEngine() {
        try {
            flutterEngine = FlutterEngine(this).apply {
                dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint.createDefault()
                )
            }

            methodChannel = MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "background_service")
            methodChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService" -> {
                        Log.d("BackgroundService", "Flutter'dan servis başlatma isteği alındı")
                        result.success("Servis başlatıldı")
                    }
                    "stopService" -> {
                        Log.d("BackgroundService", "Flutter'dan servis durdurma isteği alındı")
                        stopSelf()
                        result.success("Servis durduruldu")
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
            
            Log.d("BackgroundService", "Flutter engine başarıyla başlatıldı")
        } catch (e: Exception) {
            Log.e("BackgroundService", "Flutter engine başlatma hatası: ${e.message}")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("BackgroundService", "Servis başlatıldı")
        
        // Flutter'a servis başlatıldığını bildir
        methodChannel?.invokeMethod("serviceStarted", null)
        
        // Servis öldürülürse yeniden başlat
        return START_STICKY
    }

    override fun onDestroy() {
        Log.d("BackgroundService", "Servis durduruldu")
        
        // Wake lock'u serbest bırak
        wakeLock?.release()
        
        // Flutter engine'i durdur
        flutterEngine?.destroy()
        
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    // Uygulama kullanıcı tarafından kapatıldığında servisi yeniden başlat
    override fun onTaskRemoved(rootIntent: Intent) {
        Log.d("BackgroundService", "onTaskRemoved: Servis kaldırıldı, yeniden başlatılıyor")

        val restartServiceIntent = Intent(applicationContext, BackgroundService::class.java).apply {
            setPackage(packageName)
        }

        val restartServicePendingIntent = PendingIntent.getService(
            applicationContext,
            1,
            restartServiceIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_ONE_SHOT
        )

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            System.currentTimeMillis() + 1000,
            restartServicePendingIntent
        )

        super.onTaskRemoved(rootIntent)
    }
} 