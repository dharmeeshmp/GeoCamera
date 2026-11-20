package com.example.gps_camera_app

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.location.OnNmeaMessageListener
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.gps_camera_app/gnss_clock"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var activeResult: MethodChannel.Result? = null
    private var tempLocationListener: LocationListener? = null
    private var nmeaListener: OnNmeaMessageListener? = null
    private var timeoutRunnable: Runnable? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getTrueSatelliteTimeUtc") {
                fetchTrueSatelliteTimeUtc(result)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun cleanup(locationManager: LocationManager?) {
        try {
            timeoutRunnable?.let { mainHandler.removeCallbacks(it) }
            timeoutRunnable = null
            nmeaListener?.let { locationManager?.removeNmeaListener(it) }
            nmeaListener = null
            tempLocationListener?.let { locationManager?.removeUpdates(it) }
            tempLocationListener = null
        } catch (_: Exception) {}
    }

    @SuppressLint("MissingPermission")
    private fun fetchTrueSatelliteTimeUtc(result: MethodChannel.Result) {
        val locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (locationManager == null) {
            result.success(null)
            return
        }

        // Clean up any pending listener before starting a new request
        cleanup(locationManager)
        activeResult?.success(null)
        activeResult = result

        val localLocationListener = object : LocationListener {
            override fun onLocationChanged(location: Location) {}
            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }
        tempLocationListener = localLocationListener

        val localNmeaListener = OnNmeaMessageListener { message, _ ->
            val pending = activeResult ?: return@OnNmeaMessageListener
            try {
                if (message.contains("RMC,")) {
                    val parts = message.split(",")
                    if (parts.size >= 10 && parts[2] == "A") {
                        val rawTime = parts[1].substringBefore(".")
                        val rawDate = parts[9].trim()
                        if (rawTime.length >= 6 && rawDate.length >= 6) {
                            val hh = rawTime.substring(0, 2)
                            val mm = rawTime.substring(2, 4)
                            val ss = rawTime.substring(4, 6)

                            val dd = rawDate.substring(0, 2)
                            val MM = rawDate.substring(2, 4)
                            val yy = rawDate.substring(4, 6)

                            val isoUtcString = "20$yy-$MM-${dd}T$hh:$mm:${ss}Z"

                            activeResult = null
                            cleanup(locationManager)
                            pending.success(isoUtcString)
                        }
                    }
                }
            } catch (_: Exception) {}
        }
        nmeaListener = localNmeaListener

        val localTimeout = Runnable {
            val pending = activeResult ?: return@Runnable
            activeResult = null
            cleanup(locationManager)
            pending.success(null)
        }
        timeoutRunnable = localTimeout

        try {
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    500L,
                    0f,
                    localLocationListener,
                    Looper.getMainLooper()
                )
                locationManager.addNmeaListener(localNmeaListener, Handler(Looper.getMainLooper()))
                mainHandler.postDelayed(localTimeout, 8000L)
            } else {
                activeResult = null
                cleanup(locationManager)
                result.success(null)
            }
        } catch (e: SecurityException) {
            activeResult = null
            cleanup(locationManager)
            result.success(null)
        } catch (e: Exception) {
            activeResult = null
            cleanup(locationManager)
            result.success(null)
        }
    }

    override fun onDestroy() {
        val locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        cleanup(locationManager)
        activeResult?.success(null)
        activeResult = null
        super.onDestroy()
    }
}
