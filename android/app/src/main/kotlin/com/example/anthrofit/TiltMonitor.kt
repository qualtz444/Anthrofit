package com.example.anthrofit

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Log
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.sqrt


/**
 * Device tilt, read from the accelerometer.
 *
 * This is the one acceptance check that cannot be derived from the image.
 * Nothing in a single frame reveals whether the camera was pointing slightly
 * up or down, yet camera pitch foreshortens vertical body segments and so
 * propagates straight into femur_torso_ratio and upperbody_stature_ratio -
 * two of the three measures the recommendations depend on.
 *
 * Held upright in portrait, gravity acts along the phone's -Y axis. Tipping
 * the top away from the subject moves gravity into Z, and that is the angle
 * measured here.
 *
 * Note this checks the DEVICE, not the mount. A phone perfectly vertical on a
 * table that is itself sloping will still pass. Camera height and distance
 * remain physical controls: a marked position and a fixed stand.
 */
class TiltMonitor(context: Context) : SensorEventListener {

    companion object {
        /**
         * Maximum deviation from vertical, in degrees.
         *
         * 5 degrees at a 3 m subject distance displaces the vertical
         * projection by roughly 2%, which is at the level of the measurement
         * noise already present. Tighter than this and the check would reject
         * captures that are, in practice, fine.
         */
        const val MAX_TILT_DEG = 8f

        /**
         * Smoothing factor for the low-pass filter. Raw accelerometer output
         * jitters by a degree or two even on a stationary phone; without
         * filtering the check would flicker in and out and keep resetting the
         * capture hold.
         */
        private const val ALPHA = 0.15f
    }

    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val accelerometer: Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

    /** Smoothed gravity vector. */
    private var gx = 0f
    private var gy = -9.81f
    private var gz = 0f
    private var hasReading = false

    /** Pitch away from vertical, in degrees. 0 = phone upright. */
    val tiltDegrees: Float
        get() {
            if (!hasReading) return 0f
            // Angle between the gravity vector and the phone's own Y axis.
            val horizontal = sqrt(gx * gx + gz * gz)
            return Math.toDegrees(atan2(horizontal, abs(gy)).toDouble()).toFloat()
        }

    /** True when the phone is upright enough to measure from. */
    val isLevel: Boolean
        get() = !hasReading || tiltDegrees <= MAX_TILT_DEG

    /**
     * Returns a rejection when the phone is tilted, or null when it is fine.
     * Call once per frame before measuring.
     */
    fun checkOrNull(): Measurement.Result.Rejected? {
        if (!hasReading) return null          // no sensor: do not block capture
        val t = tiltDegrees
        Log.d("Anthrofit", "tilt ${t.toInt()}deg")
        return if (t > MAX_TILT_DEG)
            Measurement.Result.Rejected(
                "phone not upright (${t.toInt()} deg from vertical)"
            )
        else null
    }

    fun start() {
        accelerometer?.let {
            sensorManager.registerListener(
                this, it, SensorManager.SENSOR_DELAY_GAME
            )
        }
    }

    fun stop() {
        sensorManager.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_ACCELEROMETER) return
        if (!hasReading) {
            gx = event.values[0]; gy = event.values[1]; gz = event.values[2]
            hasReading = true
            return
        }
        gx += ALPHA * (event.values[0] - gx)
        gy += ALPHA * (event.values[1] - gy)
        gz += ALPHA * (event.values[2] - gz)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) { /* no-op */ }
}
