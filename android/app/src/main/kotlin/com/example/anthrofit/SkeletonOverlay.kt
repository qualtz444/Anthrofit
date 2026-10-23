package com.example.anthrofit

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import kotlin.math.max

/**
 * Draws the detected skeleton over the camera preview.
 *
 * Purely diagnostic. The guidance text tells the user what to fix; this shows
 * what the system is actually seeing, which is how a phantom detection on an
 * empty floor gets spotted rather than silently measured.
 *
 * Ported from the MediaPipe sample's OverlayView, trimmed to live-stream use.
 */
class SkeletonOverlay @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    private var result: PoseLandmarkerResult? = null
    private var imageWidth = 1
    private var imageHeight = 1

    /// Preview uses FILL_CENTER, so the image is scaled to cover the view and
    /// cropped. Using the larger of the two ratios matches that, otherwise the
    /// skeleton drifts away from the body near the edges.
    private var scaleFactor = 1f

    private val bonePaint = Paint().apply {
        color = Color.parseColor("#4DD0C7")
        strokeWidth = 8f
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        isAntiAlias = true
    }

    private val jointPaint = Paint().apply {
        color = Color.parseColor("#FFE066")
        strokeWidth = 6f
        style = Paint.Style.FILL
        isAntiAlias = true
    }

    fun setResults(
        poseResult: PoseLandmarkerResult,
        sourceHeight: Int,
        sourceWidth: Int
    ) {
        result = poseResult
        imageHeight = max(1, sourceHeight)
        imageWidth = max(1, sourceWidth)
        scaleFactor = max(
            width * 1f / imageWidth,
            height * 1f / imageHeight
        )
        postInvalidate()
    }

    fun clear() {
        result = null
        postInvalidate()
    }

    override fun draw(canvas: Canvas) {
        super.draw(canvas)
        val r = result ?: return
        if (r.landmarks().isEmpty()) return

        // Only the primary subject is drawn. A second detection means the frame
        // is rejected anyway, so drawing it would be misleading.
        val landmarks = r.landmarks()[0]

        // FILL_CENTER scales to cover and crops the excess evenly on both
        // sides, so the drawn skeleton has to be shifted by half the overflow
        // or it sits offset from the body.
        val offsetX = (width - imageWidth * scaleFactor) / 2f
        val offsetY = (height - imageHeight * scaleFactor) / 2f

        for (bone in BONES) {
            val a = landmarks.getOrNull(bone.first) ?: continue
            val b = landmarks.getOrNull(bone.second) ?: continue
            canvas.drawLine(
                offsetX + a.x() * imageWidth * scaleFactor,
                offsetY + a.y() * imageHeight * scaleFactor,
                offsetX + b.x() * imageWidth * scaleFactor,
                offsetY + b.y() * imageHeight * scaleFactor,
                bonePaint
            )
        }

        for (i in JOINTS) {
            val lm = landmarks.getOrNull(i) ?: continue
            canvas.drawCircle(
                offsetX + lm.x() * imageWidth * scaleFactor,
                offsetY + lm.y() * imageHeight * scaleFactor,
                5f,
                jointPaint
            )
        }
    }

    companion object {
        /**
         * Landmark pairs to connect. Only the segments that matter for
         * measurement are drawn — face and hand detail would clutter the view
         * without telling anyone anything useful.
         */
        private val BONES = listOf(
            11 to 12,   // shoulders
            11 to 23, 12 to 24,   // torso sides
            23 to 24,   // hips
            11 to 13, 13 to 15,   // left arm
            12 to 14, 14 to 16,   // right arm
            23 to 25, 25 to 27,   // left leg
            24 to 26, 26 to 28    // right leg
        )
        private val JOINTS = listOf(11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28)
    }
}
