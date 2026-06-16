package com.example.apk_tws

import android.Manifest
import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothProfile
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.FrameLayout
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject

class TwsBackgroundService : Service() {
    private val mainHandler = Handler(Looper.getMainLooper())

    private var overlayView: View? = null
    private lateinit var windowManager: WindowManager
    private lateinit var audioManager: AudioManager
    private var lastEventDevice: String? = null
    private var lastEventStatus: String? = null
    private var lastEventAtMs: Long = 0L
    private val connectedAudioRoutes = linkedSetOf<String>()

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val action = intent.action ?: return
            Log.d(TAG, "Bluetooth broadcast received: $action")
            val device = getBluetoothDevice(intent)
                ?: return
            val name = device.name ?: device.address ?: "Unknown device"
            if (!isTargetDeviceName(name)) {
                Log.d(TAG, "Ignoring non-target device: $name")
                return
            }

            val status = statusFromIntent(intent) ?: return
            publishConnectionEvent(name, status, extractBatteryLevel(device))
        }
    }

    private val audioDeviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
            handleAudioDevicesChanged(addedDevices, connected = true)
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
            handleAudioDevicesChanged(removedDevices, connected = false)
        }
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        Log.d(TAG, "TwsBackgroundService created")
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        createChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Listening for KiiP DTS16"))

        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
            addAction(BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED)
            addAction(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, RECEIVER_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        seedConnectedAudioRoutes()
        audioManager.registerAudioDeviceCallback(audioDeviceCallback, mainHandler)
        mainHandler.postDelayed(
            { emitConnectedStateForExistingRouteIfNeeded() },
            STARTUP_ROUTE_SYNC_DELAY_MS
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_SHOW_PREVIEW) {
            Log.d(TAG, "Received preview popup request")
            mainHandler.post {
                showConnectionOverlay("KiiP DTS16", -1)
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        Log.d(TAG, "TwsBackgroundService destroyed")
        isRunning = false
        removeOverlayImmediately()
        audioManager.unregisterAudioDeviceCallback(audioDeviceCallback)
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

    private fun extractBatteryLevel(device: BluetoothDevice?): Int {
        if (device == null) {
            return -1
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return -1
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return -1
        }
        return runCatching {
            // Avoid a hard compile-time dependency on newer BluetoothDevice APIs.
            val method = BluetoothDevice::class.java.getMethod("getBatteryLevel")
            method.invoke(device) as? Int ?: -1
        }.getOrDefault(-1)
    }

    private fun handleAudioDevicesChanged(
        devices: Array<out AudioDeviceInfo>,
        connected: Boolean
    ) {
        devices.forEach { device ->
            if (!isBluetoothAudioType(device.type)) {
                return@forEach
            }

            val deviceName = device.productName?.toString()?.trim().orEmpty()
            if (!isTargetDeviceName(deviceName)) {
                return@forEach
            }

            val routeKey = "${device.type}:$deviceName"
            if (connected) {
                if (!connectedAudioRoutes.add(routeKey)) {
                    Log.d(TAG, "Ignoring duplicate audio route add: $routeKey")
                    return@forEach
                }
            } else {
                if (!connectedAudioRoutes.remove(routeKey)) {
                    Log.d(TAG, "Ignoring duplicate audio route removal: $routeKey")
                    return@forEach
                }
            }

            Log.d(TAG, "Audio route ${if (connected) "added" else "removed"}: $routeKey")
            publishConnectionEvent(
                deviceName.ifBlank { "KiiP DTS16" },
                if (connected) "connected" else "disconnected",
                extractBatteryLevel(findBondedDeviceByName(deviceName))
            )
        }
    }

    private fun seedConnectedAudioRoutes() {
        val currentDevices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        currentDevices.forEach { device ->
            if (!isBluetoothAudioType(device.type)) {
                return@forEach
            }
            val deviceName = device.productName?.toString()?.trim().orEmpty()
            if (!isTargetDeviceName(deviceName)) {
                return@forEach
            }
            connectedAudioRoutes.add("${device.type}:$deviceName")
        }
        Log.d(TAG, "Seeded ${connectedAudioRoutes.size} connected audio route(s)")
    }

    private fun emitConnectedStateForExistingRouteIfNeeded() {
        val currentTarget = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .firstOrNull { device ->
                isBluetoothAudioType(device.type) &&
                    isTargetDeviceName(device.productName?.toString())
            } ?: run {
            Log.d(TAG, "No active KiiP route found during startup sync")
            return
        }

        val latestEvent = readLatestEvent(this)
        val latestStatus = latestEvent?.get("status") as? String
        val latestDeviceName = latestEvent?.get("deviceName") as? String
        val latestTimestamp = (latestEvent?.get("timestamp") as? String)
            ?.let(java.time.Instant::parse)
            ?.toEpochMilli()
            ?: 0L
        val now = System.currentTimeMillis()
        val currentName = currentTarget.productName?.toString()?.trim().orEmpty()

        val alreadySyncedRecently = latestStatus == "connected" &&
            latestDeviceName.equals(currentName, ignoreCase = true) &&
            now - latestTimestamp < STARTUP_ROUTE_RECENT_EVENT_WINDOW_MS
        if (alreadySyncedRecently) {
            Log.d(TAG, "Skipping startup sync for $currentName because latest event is still fresh")
            return
        }

        Log.d(TAG, "Startup sync emitting connected event for ${currentName.ifBlank { "KiiP DTS16" }}")
        publishConnectionEvent(
            currentName.ifBlank { "KiiP DTS16" },
            "connected",
            extractBatteryLevel(findBondedDeviceByName(currentName))
        )
    }

    private fun getBluetoothDevice(intent: Intent): BluetoothDevice? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }
    }

    private fun statusFromIntent(intent: Intent): String? {
        return when (intent.action) {
            BluetoothDevice.ACTION_ACL_CONNECTED -> "connected"
            BluetoothDevice.ACTION_ACL_DISCONNECTED -> "disconnected"
            BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED,
            BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED -> {
                when (intent.getIntExtra(BluetoothProfile.EXTRA_STATE, -1)) {
                    BluetoothProfile.STATE_CONNECTED -> "connected"
                    BluetoothProfile.STATE_DISCONNECTED -> "disconnected"
                    else -> null
                }
            }
            else -> null
        }
    }

    private fun shouldIgnoreDuplicateEvent(deviceKey: String, status: String): Boolean {
        val now = System.currentTimeMillis()
        val duplicated = lastEventDevice == deviceKey &&
            lastEventStatus == status &&
            now - lastEventAtMs < DUPLICATE_EVENT_WINDOW_MS
        if (!duplicated) {
            lastEventDevice = deviceKey
            lastEventStatus = status
            lastEventAtMs = now
        }
        return duplicated
    }

    private fun publishConnectionEvent(deviceName: String, status: String, batteryLevel: Int) {
        val dedupeKey = deviceName.ifBlank { "KiiP DTS16" }
        if (shouldIgnoreDuplicateEvent(dedupeKey, status)) {
            Log.d(TAG, "Ignoring duplicate published event: $dedupeKey $status")
            return
        }

        val timestamp = System.currentTimeMillis()
        persistEvent(dedupeKey, status, timestamp, batteryLevel)
        Log.d(TAG, "Publishing event: $dedupeKey $status battery=$batteryLevel")
        val eventIntent = Intent(MainActivity.EVENT_ACTION).apply {
            putExtra("deviceName", dedupeKey)
            putExtra("status", status)
            putExtra("timestamp", timestamp)
            putExtra("batteryLevel", batteryLevel)
            setPackage(packageName)
        }
        sendBroadcast(eventIntent)

        if (status == "connected") {
            mainHandler.post {
                showConnectionOverlay(dedupeKey, batteryLevel)
            }
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification("$dedupeKey $status"))
    }

    private fun persistEvent(
        deviceName: String,
        status: String,
        timestamp: Long,
        batteryLevel: Int
    ) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_EVENTS, null)
        val currentEvents = runCatching {
            if (raw.isNullOrBlank()) JSONArray() else JSONArray(raw)
        }.getOrElse { JSONArray() }

        val updatedEvents = JSONArray().apply {
            put(
                JSONObject().apply {
                    put("deviceName", deviceName)
                    put("status", status)
                    put("timestamp", timestamp)
                    if (batteryLevel >= 0) {
                        put("batteryLevel", batteryLevel)
                    }
                }
            )

            for (index in 0 until minOf(currentEvents.length(), MAX_STORED_EVENTS - 1)) {
                put(currentEvents.getJSONObject(index))
            }
        }

        prefs.edit().putString(KEY_EVENTS, updatedEvents.toString()).apply()
    }

    private fun isBluetoothAudioType(type: Int): Boolean {
        return when (type) {
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_SPEAKER -> true
            else -> false
        }
    }

    private fun isTargetDeviceName(name: String?): Boolean {
        val normalized = name?.trim()?.lowercase().orEmpty()
        return normalized.contains("kiip") || normalized.contains("dts16")
    }

    private fun findBondedDeviceByName(name: String): BluetoothDevice? {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return null
        }

        return BluetoothAdapter.getDefaultAdapter()
            ?.bondedDevices
            ?.firstOrNull { bonded ->
                val bondedName = bonded.name?.trim().orEmpty()
                bondedName.equals(name, ignoreCase = true) || isTargetDeviceName(bondedName)
            }
    }

    private fun showConnectionOverlay(deviceName: String, batteryLevel: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Log.d(TAG, "Skipping overlay because SYSTEM_ALERT_WINDOW is not granted")
            return
        }

        removeOverlayImmediately()

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(22), dp(18), dp(22), dp(20))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(28).toFloat()
                setColor(0xFFFCFEFF.toInt())
                setStroke(dp(1), 0xFFD7E6F5.toInt())
            }
            elevation = dp(12).toFloat()
        }
        container.alpha = 0f

        val imageFrame = LinearLayout(this).apply {
            gravity = Gravity.CENTER
            setPadding(dp(12), dp(12), dp(12), dp(12))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(24).toFloat()
                setColor(0xFFF7F3EB.toInt())
            }
        }
        val productImage = ImageView(this).apply {
            setImageResource(R.drawable.kiip_dts16_popup)
            adjustViewBounds = true
            scaleType = ImageView.ScaleType.FIT_CENTER
            layoutParams = LinearLayout.LayoutParams(dp(220), dp(220))
        }
        imageFrame.addView(productImage)

        val statusBadge = TextView(this).apply {
            text = "KiiP DTS16"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(0xFF194B8C.toInt())
            gravity = Gravity.CENTER
            setPadding(dp(12), dp(6), dp(12), dp(6))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(99).toFloat()
                setColor(0xFFE8F1FB.toInt())
            }
        }

        val title = TextView(this).apply {
            text = deviceName
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(0xFF0F172A.toInt())
            gravity = Gravity.CENTER
        }
        val subtitle = TextView(this).apply {
            text = if (batteryLevel >= 0) {
                "Connected | Battery $batteryLevel%"
            } else {
                "Connected"
            }
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTextColor(0xFF52607A.toInt())
            gravity = Gravity.CENTER
        }
        val okButton = Button(this).apply {
            text = "OK"
            isAllCaps = false
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(0xFFFFFFFF.toInt())
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(18).toFloat()
                setColor(0xFF194B8C.toInt())
            }
            minWidth = dp(120)
            setPadding(dp(22), dp(10), dp(22), dp(10))
            setOnClickListener { dismissOverlayAnimated() }
        }

        container.addView(imageFrame)
        container.addView(
            statusBadge,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dp(14)
            }
        )
        container.addView(title)
        container.addView(
            subtitle,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dp(4)
            }
        )
        container.addView(
            okButton,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dp(18)
            }
        )

        val root = FrameLayout(this).apply {
            setBackgroundColor(0x00000000)
            isClickable = true
            isFocusable = false
            setOnClickListener {
                dismissOverlayAnimated()
            }
            addView(
                container,
                FrameLayout.LayoutParams(
                    dp(340),
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                ).apply {
                    bottomMargin = dp(18)
                }
            )
        }
        container.setOnClickListener {
            // Consume taps on the card itself.
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        }

        runCatching {
            Log.d(TAG, "Showing overlay for $deviceName")
            windowManager.addView(root, params)
            overlayView = root
            container.post {
                container.translationY = dp(280).toFloat()
                AnimatorSet().apply {
                    playTogether(
                        ObjectAnimator.ofFloat(container, View.TRANSLATION_Y, container.translationY, 0f),
                        ObjectAnimator.ofFloat(container, View.ALPHA, 0f, 1f)
                    )
                    duration = 420L
                    interpolator = DecelerateInterpolator()
                    start()
                }
            }
        }.onFailure { error ->
            Log.e(TAG, "Failed to show overlay for $deviceName", error)
        }
    }

    private fun dismissOverlayAnimated() {
        overlayView?.let { view ->
            val card = (view as? FrameLayout)?.getChildAt(0) ?: view
            card.animate()
                .translationY(dp(220).toFloat())
                .alpha(0f)
                .setDuration(220L)
                .setInterpolator(DecelerateInterpolator())
                .setListener(
                    object : AnimatorListenerAdapter() {
                        override fun onAnimationEnd(animation: Animator) {
                            removeOverlayImmediately()
                        }

                        override fun onAnimationCancel(animation: Animator) {
                            removeOverlayImmediately()
                        }
                    }
                )
                .start()
        } ?: removeOverlayImmediately()
    }

    private fun removeOverlayImmediately() {
        mainHandler.post {
            overlayView?.animate()?.setListener(null)?.cancel()
            overlayView?.let { view ->
                runCatching {
                    windowManager.removeView(view)
                }
            }
            overlayView = null
        }
    }

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics
        ).toInt()
    }

    companion object {
        private const val CHANNEL_ID = "kiip_dts16_background"
        private const val NOTIFICATION_ID = 1601
        private const val DUPLICATE_EVENT_WINDOW_MS = 1500L
        private const val TAG = "KiiPPopup"
        private const val PREFS_NAME = "kiip_dts16_monitor"
        private const val KEY_EVENTS = "connection_events"
        private const val MAX_STORED_EVENTS = 20
        private const val STARTUP_ROUTE_SYNC_DELAY_MS = 900L
        private const val STARTUP_ROUTE_RECENT_EVENT_WINDOW_MS = 15_000L
        const val ACTION_SHOW_PREVIEW = "com.example.apk_tws.SHOW_PREVIEW"
        @Volatile
        var isRunning: Boolean = false

        fun readStoredEvents(context: Context): List<HashMap<String, Any?>> {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY_EVENTS, null) ?: return emptyList()
            val jsonArray = runCatching { JSONArray(raw) }.getOrElse { return emptyList() }

            return buildList {
                for (index in 0 until jsonArray.length()) {
                    val item = jsonArray.optJSONObject(index) ?: continue
                    add(
                        hashMapOf(
                            "deviceName" to item.optString("deviceName", "KiiP DTS16"),
                            "status" to item.optString("status", "unknown"),
                            "timestamp" to java.time.Instant.ofEpochMilli(
                                item.optLong("timestamp", System.currentTimeMillis())
                            ).toString(),
                            "batteryLevel" to item.optInt("batteryLevel", -1).takeIf { it >= 0 }
                        )
                    )
                }
            }
        }

        fun readLatestEvent(context: Context): HashMap<String, Any?>? {
            return readStoredEvents(context).firstOrNull()
        }
    }
}
