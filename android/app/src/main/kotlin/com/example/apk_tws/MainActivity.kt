package com.example.apk_tws

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
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
                    val serviceIntent = Intent(this, TwsBackgroundService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                    result.success(null)
                }

                "stopService" -> {
                    stopService(Intent(this, TwsBackgroundService::class.java))
                    result.success(null)
                }

                "getInitialEvent" -> result.success(pendingEvent)
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
        if (!receiverRegistered) {
            registerReceiver(receiver, IntentFilter(EVENT_ACTION))
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

    companion object {
        const val EVENT_ACTION = "com.example.apk_tws.CONNECTION_EVENT"
        private const val METHOD_CHANNEL = "apk_tws/service"
        private const val EVENT_CHANNEL = "apk_tws/events"
        private var pendingEvent: HashMap<String, Any?>? = null
    }
}
