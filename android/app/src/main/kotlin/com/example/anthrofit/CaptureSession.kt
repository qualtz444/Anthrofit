package com.example.anthrofit

import android.os.SystemClock

/**
 * Capture flow.
 *
 * The user is standing several feet from a propped-up phone and cannot reach
 * the shutter, so capture is automatic: every frame is checked, the user is
 * told what to fix, and recording starts once the checks have held steady for
 * HOLD_MS. Frames are then collected until FRAME_TARGET is reached and the
 * median is taken.
 *
 * The stillness requirement is not cosmetic. Live logging showed femur/torso
 * drifting from 0.708 to 0.750 over the first second while the subject was
 * still settling into position; waiting for a steady hold keeps those frames
 * out of the measurement.
 */

class CaptureSession(
    private val listener: Listener
) {

    companion object {
        /** How long every check must hold before recording begins. */
        const val HOLD_MS = 1500L

        /** Frames to collect once recording starts. */
        const val FRAME_TARGET = 20

        /** Minimum usable frames for a result to be produced. */
        const val MIN_ACCEPTED = 15

        /** Abandon a recording that cannot gather enough frames in time. */
        const val RECORD_TIMEOUT_MS = 10000L
    }

    enum class State { IDLE, POSITIONING, HOLDING, RECORDING, DONE }

    interface Listener {
        /** Called on every frame so the UI can show guidance. */
        fun onStateChanged(state: State, message: String, holdProgress: Float)

        /** Called once when a capture completes successfully. */
        fun onCaptureComplete(result: Measurement.Aggregate)

        /** Called when a recording had to be abandoned. */
        fun onCaptureFailed(reason: String)
    }

    var state: State = State.IDLE
        private set

    private var holdStartMs = 0L
    private var recordStartMs = 0L
    private val frames = mutableListOf<Measurement.Result>()

    /** Begin looking for a valid pose. Call when the user opens the scan screen. */
    fun start() {
        state = State.POSITIONING
        holdStartMs = 0L
        frames.clear()
        listener.onStateChanged(state, "Stand so your whole body is in frame", 0f)
    }

    /** Stop and discard any partial capture. */
    fun cancel() {
        state = State.IDLE
        frames.clear()
    }

    /**
     * Feed one frame's measurement result. Call from the pose landmarker
     * callback, once per frame.
     */
    fun onFrame(result: Measurement.Result) {
        when (state) {
            State.IDLE, State.DONE -> return

            State.POSITIONING, State.HOLDING -> handlePositioning(result)

            State.RECORDING -> handleRecording(result)
        }
    }

    private fun handlePositioning(result: Measurement.Result) {
        val now = SystemClock.uptimeMillis()

        if (result is Measurement.Result.Rejected) {
            // Any failure resets the hold: we want a steady pose, not a
            // momentary one.
            holdStartMs = 0L
            state = State.POSITIONING
            listener.onStateChanged(state, guidanceFor(result.reason), 0f)
            return
        }

        if (holdStartMs == 0L) {
            holdStartMs = now
            state = State.HOLDING
        }

        val held = now - holdStartMs
        if (held >= HOLD_MS) {
            state = State.RECORDING
            recordStartMs = now
            frames.clear()
            frames.add(result)
            listener.onStateChanged(state, "Measuring - keep still", 1f)
        } else {
            listener.onStateChanged(
                state, "Hold still", held.toFloat() / HOLD_MS
            )
        }
    }

    private fun handleRecording(result: Measurement.Result) {
        frames.add(result)

        val progress = frames.size.toFloat() / FRAME_TARGET
        listener.onStateChanged(state, "Measuring - keep still", progress)

        val timedOut = SystemClock.uptimeMillis() - recordStartMs > RECORD_TIMEOUT_MS
        if (frames.size < FRAME_TARGET && !timedOut) return

        val agg = Measurement.aggregate(frames, MIN_ACCEPTED)
        state = State.DONE

        if (agg == null) {
            val usable = frames.count { it is Measurement.Result.Ok }
            val rejects = frames.filterIsInstance<Measurement.Result.Rejected>()
            listener.onCaptureFailed(
                if (rejects.isEmpty())
                    "Not enough frames were captured in time. Try holding still a little longer."
                else
                    "Only $usable of ${frames.size} frames were usable. Most common " +
                            "problem: ${rejects.groupingBy { it.reason }.eachCount()
                                .maxByOrNull { it.value }?.key}"
            )
        }
         else {
            listener.onCaptureComplete(agg)
        }
    }

    /** Turn a rejection reason into something a user standing 3 m away can act on. */
    private fun guidanceFor(reason: String): String = when {
        reason.contains("full body") -> "Step back so your whole body fits"
        reason.contains("square to camera") -> "Turn to face the camera directly"
        reason.contains("visibility") -> "Make sure nothing is blocking your body"
        reason.contains("too close to the body") -> "Move your arms further from your sides"
        reason.contains("raised too high") -> "Lower your arms - about 25 degrees out"
        reason.contains("arm abduction") -> "Move your arms further from your sides"
        reason.contains("incomplete landmark") -> "Step into frame"
        reason.contains("too blurry") -> "Hold the phone steady"
        reason.contains("exposure") -> "Move somewhere more evenly lit"
        reason.contains("clipped") -> "Too much glare - move away from the light"
        reason.contains("no person detected") -> "Step into frame"
        reason.contains("not upright") -> "Stand the phone up straight"
        reason.contains("more than one person") ->
            "Only one person in frame - move away from mirrors"
        else -> reason
    }
}