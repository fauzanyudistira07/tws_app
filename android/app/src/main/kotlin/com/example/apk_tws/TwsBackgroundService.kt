package com.example.apk_tws

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class TwsBackgroundService : Service() {
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val action = intent.action ?: return
            if (action != BluetoothDevice.ACTION_ACL_CONNECTED &&
                action != BluetoothDevice.ACTION_ACL_DISCONNECTED
            ) {
                return
            }

            val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                ?: return
            val name = device.name ?: device.address ?: "Unknown device"
            if (!name.contains("KiiP DTS16", ignoreCase = true)) {
                return
            }

            val status = if (action == BluetoothDevice.ACTION_ACL_CONNECTED) {
                "connected"
            } else {
                "disconnected"
            }

            val eventIntent = Intent(MainActivity.EVENT_ACTION).apply {
                putExtra("deviceName", name)
                putExtra("status", status)
                putExtra("timestamp", System.currentTimeMillis())
                putExtra("batteryLevel", extractBatteryLevel(device))
                setPackage(packageName)
            }
            sendBroadcast(eventIntent)

            if (status == "connected") {
                val launchIntent = Intent(this@TwsBackgroundService, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtras(eventIntent)
                }
                startActivity(launchIntent)
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, buildNotification("$name $status"))
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Listening for KiiP DTS16"))
        registerReceiver(
            receiver,
            IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
                addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
            }
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        unregisterReceiver(receiver)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "KiiP DTS16 Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(message: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("KiiP DTS16 Monitor")
            .setContentText(message)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .build()
    }

    private fun extractBatteryLevel(device: BluetoothDevice): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return -1
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return -1
        }
        return device.batteryLevel
    }

    companion object {
        private const val CHANNEL_ID = "kiip_dts16_background"
        private const val NOTIFICATION_ID = 1601
    }
}
