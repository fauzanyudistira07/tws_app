package com.example.apk_tws

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var events: EventChannel.EventSink? = null
    private var receiverRegistered = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            intent?.let(::publishEvent)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    ensureServiceRunning()
                    result.success(null)
                }

                "stopService" -> {
                    stopService(Intent(this, TwsBackgroundService::class.java))
                    result.success(null)
                }

                "isServiceRunning" -> result.success(TwsBackgroundService.isRunning)
                "hasOverlayPermission" -> {
                    result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)
                    )
                }
                "getInitialEvent" -> result.success(
                    pendingEvent ?: TwsBackgroundService.readLatestEvent(this)
                )
                "getEventHistory" -> result.success(TwsBackgroundService.readStoredEvents(this))
                "showPreviewPopup" -> {
                    ensureServiceRunning()
                    val intent = Intent(this, TwsBackgroundService::class.java).apply {
                        action = TwsBackgroundService.ACTION_SHOW_PREVIEW
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    events = sink
                    pendingEvent?.let(sink::success)
                }

                override fun onCancel(arguments: Any?) {
                    events = null
                }
            }
        )
    }

    override fun onStart() {
        super.onStart()
        ensureServiceRunning()
        if (!receiverRegistered) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, IntentFilter(EVENT_ACTION), RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(receiver, IntentFilter(EVENT_ACTION))
            }
            receiverRegistered = true
        }
        intent?.let(::publishEvent)
    }

    override fun onStop() {
        if (receiverRegistered) {
            unregisterReceiver(receiver)
            receiverRegistered = false
        }
        super.onStop()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        publishEvent(intent)
    }

    private fun publishEvent(intent: Intent) {
        val deviceName = intent.getStringExtra("deviceName") ?: return
        Log.d(TAG, "Delivering event to Flutter: $deviceName ${intent.getStringExtra("status")}")
        pendingEvent = hashMapOf(
            "deviceName" to deviceName,
            "status" to (intent.getStringExtra("status") ?: "unknown"),
            "timestamp" to java.time.Instant.ofEpochMilli(
                intent.getLongExtra("timestamp", System.currentTimeMillis())
            ).toString(),
            "batteryLevel" to intent.getIntExtra("batteryLevel", -1).takeIf { it >= 0 }
        )
        events?.success(pendingEvent)
    }

    private fun ensureServiceRunning() {
        val hasBluetoothConnectPermission = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.BLUETOOTH_CONNECT
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasBluetoothConnectPermission) {
            Log.d(TAG, "Skipping service start because BLUETOOTH_CONNECT is not granted")
            return
        }

        val serviceIntent = Intent(this, TwsBackgroundService::class.java)
        Log.d(TAG, "Ensuring background service is running")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    companion object {
        const val EVENT_ACTION = "com.example.apk_tws.CONNECTION_EVENT"
        private const val METHOD_CHANNEL = "apk_tws/service"
        private const val EVENT_CHANNEL = "apk_tws/events"
        private const val TAG = "KiiPPopup"
        private var pendingEvent: HashMap<String, Any?>? = null
    }
}
