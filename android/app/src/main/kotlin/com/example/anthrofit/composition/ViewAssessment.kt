package com.example.anthrofit.composition

import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/** One pose landmark, normalised 0..1 across the frame. */
data class Landmark(
    val x: Float,
    val y: Float,
    val z: Float = 0f,
    val visibility: Float = 0f,
)

/**
 * Judges single frames for the body composition capture: is the person in
 * the right position, and does their outline cover the body the pose model
 * found?
 *
 * Ported from the bodycomp project's scan.js (frameAssessment) and mask.js
 * (qualityCheck), MIT. Pure Kotlin, no Android types.
 *
 * Refusing a frame is the point. A bad silhouette does not fail loudly; it
 * produces a confident, wrong body-fat figure.
 */
object ViewAssessment {

    // BlazePose indices
    const val NOSE = 0
    const val L_SHOULDER = 11
    const val R_SHOULDER = 12
    const val L_WRIST = 15
    const val R_WRIST = 16
    const val L_HIP = 23
    const val R_HIP = 24
    const val L_ANKLE = 27
    const val R_ANKLE = 28

    /**
     * Deliberately forgiving: a real person jitters, and requiring every check
     * to pass on one frame meant it often passed on none. Nothing here is the
     * last line of defence; [maskCheck] still rejects a bad outline.
     */
    object Tolerance {
        const val VISIBILITY = 0.35f
        const val CLEARANCE = 0.45f   // wrist distance from hip, in shoulder widths
        const val TILT = 0.22f        // shoulder level
        const val MARGIN = 0.02f      // how close to the frame edge is "clipped"
    }

    /** Shoulder span / torso length above which the person counts as facing the camera. */
    private const val FACING_RATIO = 0.5f

    class Assessment(
        val usable: Boolean,
        /** Shoulder span / torso length, in pixels. High facing the camera, low in profile. */
        val ratio: Float,
        /** Shoulder span / body height. About 0.20-0.26 square on, 0.05-0.10 in profile. */
        val spanRatio: Float,
        val tilt: Float,
        val minVisibility: Float,
        val issues: List<String>,
    )

    private val UNUSABLE = Assessment(false, 0f, 0f, 0f, 0f, listOf("No person detected."))

    fun frame(
        lm: List<Landmark>?,
        width: Int,
        height: Int,
        assumeFacing: Boolean = false,
    ): Assessment {
        if (lm == null || lm.size < 33) return UNUSABLE
        val issues = ArrayList<String>()

        fun vis(i: Int) = lm[i].visibility
        fun inFrame(i: Int) =
            lm[i].y > 0.01f && lm[i].y < 0.995f && lm[i].x > 0.005f && lm[i].x < 0.995f
        // Visibility alone is unreliable on lighter models, so a landmark counts
        // as present if it is confident OR sitting inside the frame.
        fun present(i: Int) =
            vis(i) >= Tolerance.VISIBILITY || (vis(i) >= 0.28f && inFrame(i))

        if (!present(NOSE)) issues.add("Move the camera back - your head is out of frame.")
        if (!present(L_ANKLE) && !present(R_ANKLE)) {
            issues.add("Move the camera back - your feet must be in frame.")
        }

        val xs = listOf(L_SHOULDER, R_SHOULDER, L_HIP, R_HIP).map { lm[it].x }
        if (xs.min() < Tolerance.MARGIN || xs.max() > 1 - Tolerance.MARGIN) {
            issues.add("Centre yourself in the frame.")
        }

        val w = width.toFloat()
        val h = height.toFloat()
        val lShX = lm[L_SHOULDER].x * w
        val lShY = lm[L_SHOULDER].y * h
        val rShX = lm[R_SHOULDER].x * w
        val rShY = lm[R_SHOULDER].y * h
        val shoulderPx = hypot(lShX - rShX, lShY - rShY)
        val midShY = (lShY + rShY) / 2
        val midHipY = (lm[L_HIP].y * h + lm[R_HIP].y * h) / 2
        val torsoPx = abs(midHipY - midShY).let { if (it == 0f) 1e-6f else it }
        val ratio = shoulderPx / torsoPx

        // Nose to the left ankle, as the reference does.
        val bodyPx = abs(lm[L_ANKLE].y * h - lm[NOSE].y * h)
        val spanRatio = if (bodyPx > 1f) shoulderPx / bodyPx else 0f

        val shoulderSpanX = abs(lm[L_SHOULDER].x * w - lm[R_SHOULDER].x * w)
            .let { if (it == 0f) 1e-6f else it }
        val tilt = abs(lShY - rShY) / shoulderSpanX
        val hipX = (lm[L_HIP].x * w + lm[R_HIP].x * w) / 2
        val clearance = min(
            abs(lm[L_WRIST].x * w - hipX),
            abs(lm[R_WRIST].x * w - hipX),
        ) / shoulderSpanX

        // Arm and tilt checks only mean something facing the camera; in profile
        // the shoulders overlap. [assumeFacing] is set for the front step,
        // where the person is square on by definition. Without it a narrow
        // build, or arms held in front, would skip the arm check and be waved
        // through.
        val facing = assumeFacing || ratio > FACING_RATIO
        if (facing && clearance < Tolerance.CLEARANCE) {
            issues.add("Hold your arms out, about 30 degrees.")
        }
        if (facing && tilt > Tolerance.TILT) {
            issues.add("Level your shoulders and face the camera square on.")
        }

        val minVis = minOf(
            vis(NOSE), vis(L_ANKLE), vis(R_ANKLE), vis(L_SHOULDER), vis(R_SHOULDER),
        )
        return Assessment(issues.isEmpty(), ratio, spanRatio, tilt, minVis, issues)
    }

    class MaskCheck(val usable: Boolean, val issues: List<String>, val coveragePct: Float)

    /**
     * Does the outline actually cover the body the pose model found?
     *
     * Pose landmarks survive low contrast that segmentation does not. When the
     * outline stops well above the ankles it has lost the legs, which silently
     * inflates every circumference. This check does not depend on landmark
     * confidence, so it holds whichever pose model ships.
     */
    fun maskCheck(mask: ByteArray, w: Int, h: Int, lm: List<Landmark>?): MaskCheck {
        val b = MaskOps.bounds(mask, w, h)
        if (b.isEmpty) return MaskCheck(false, listOf("No person found in this frame."), 0f)

        val issues = ArrayList<String>()
        val coverage = 100f * b.area / (w * h)
        if (coverage < 4f) issues.add("You are too small in the frame - move closer.")
        if (coverage > 60f) issues.add("You fill the frame - step back so your whole body fits.")
        if (b.top <= 1 || b.bottom >= h - 2) {
            issues.add("Your body is cut off at the top or bottom of the frame.")
        }
        if (b.left <= 1 || b.right >= w - 2) {
            issues.add("Your body is cut off at the left or right edge.")
        }

        if (lm == null || lm.size < 33) {
            issues.add("Could not detect a person - check the lighting.")
            return MaskCheck(false, issues, coverage)
        }

        val poseTop = lm[NOSE].y
        val poseBottom = max(lm[L_ANKLE].y, lm[R_ANKLE].y)
        val maskTop = b.top.toFloat() / h
        val maskBottom = b.bottom.toFloat() / h
        if (poseBottom - maskBottom > 0.05f) {
            issues.add(
                "Your outline is missing your legs or feet - stand against a " +
                    "background that contrasts with your clothes."
            )
        }
        if (maskTop - poseTop > 0.05f) {
            issues.add(
                "Your outline is missing your head - increase the contrast with " +
                    "the background."
            )
        }
        return MaskCheck(issues.isEmpty(), issues, coverage)
    }
}
