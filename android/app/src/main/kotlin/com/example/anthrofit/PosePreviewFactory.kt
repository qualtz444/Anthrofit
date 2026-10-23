package com.example.anthrofit

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.os.SystemClock
import android.util.Log
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.FrameLayout
import androidx.camera.core.AspectRatio
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.roundToInt

/**
 * A live pose stream for the guided set's rep counter.
 *
 * Uses its own MediaPipe Pose Landmarker set up for speed (RepPoseDetector,
 * below) and runs no capture flow and makes no measurements: it only sends each
 * frame's 33 world landmarks to Flutter, where the reps are counted. Kept
 * apart from ScanPreview so the measurement pipeline is not touched.
 *
 * Contract (matches lib/reps/pose_source.dart):
 *   view type   anthrofit/pose_preview
 *   methods     anthrofit/pose_<id>          start, switchCamera
 *   events      anthrofit/pose_events_<id>   one map per processed frame:
 *     {"timestampMs": Long,
 *      "landmarks": [[x, y, z, visibility] x 33]}   world landmarks, metres
 *   "landmarks" is empty when no person is found.
 *
 * Nothing is recorded or saved: frames stay on this device and are dropped
 * as soon as MediaPipe has read them.
 */
class PosePreviewFactory(
    private val messenger: BinaryMessenger,
    private val lifecycleOwner: () -> LifecycleOwner?
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    companion object {
        const val VIEW_TYPE = "anthrofit/pose_preview"
    }

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        PosePreview(context, viewId, messenger, lifecycleOwner)
}

class PosePreview(
    private val context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    private val lifecycleOwner: () -> LifecycleOwner?
) : PlatformView {

    companion object {
        private const val TAG = "AnthrofitPose"
    }

    private val previewView = PreviewView(context).apply {
        scaleType = PreviewView.ScaleType.FILL_CENTER
    }
    private val skeleton = SkeletonOverlay(context)
    private val methods = MethodChannel(messenger, "anthrofit/pose_$viewId")
    private val events = EventChannel(messenger, "anthrofit/pose_events_$viewId")
    private var sink: EventChannel.EventSink? = null

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private var detector: RepPoseDetector? = null
    private var provider: ProcessCameraProvider? = null
    private val container = FrameLayout(context).apply {
        addView(previewView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(skeleton, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    @Volatile private var disposed = false

    /** Frames are only sent once Flutter has asked to start. */
    @Volatile private var streaming = false

    // Front camera first: the phone is propped up facing the person, who
    // needs to see the count on screen. The switch button changes it.
    private var lensFacing = CameraSelector.LENS_FACING_FRONT

    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                this@PosePreview.sink = sink
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })

        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> { streaming = true; result.success(null) }
                "switchCamera" -> { switchCamera(); result.success(null) }
                else -> result.notImplemented()
            }
        }

        container.post { bindCamera() }
        executor.execute {
            // Created and used on this one thread: the GPU delegate requires it.
            detector = RepPoseDetector(
                context,
                onResult = { result, height, width -> onResults(result, height, width) },
                onFailure = { message -> onError(message) }
            ).also { it.setUp() }
        }
    }

    override fun getView(): View = container

    private fun switchCamera() {
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK) {
            CameraSelector.LENS_FACING_FRONT
        } else {
            CameraSelector.LENS_FACING_BACK
        }
        ContextCompat.getMainExecutor(context).execute { bindCamera() }
    }

    // ---- Camera -------------------------------------------------------------

    private fun bindCamera() {
        if (disposed) return
        val owner = lifecycleOwner() ?: run {
            Log.e(TAG, "no lifecycle owner; cannot bind camera")
            return
        }
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            if (disposed) return@addListener
            provider = future.get()
            val selector = CameraSelector.Builder()
                .requireLensFacing(lensFacing)
                .build()
            val preview = Preview.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .build()
            val analyzer = ImageAnalysis.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                .build()
                .also { it.setAnalyzer(executor) { image -> detect(image) } }
            try {
                provider?.unbindAll()
                provider?.bindToLifecycle(owner, selector, preview, analyzer)
                preview.setSurfaceProvider(previewView.surfaceProvider)
            } catch (e: Exception) {
                // Flutter reads a silent stream as "nobody in view", and the
                // user can still count by hand.
                Log.e(TAG, "camera binding failed", e)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun detect(imageProxy: ImageProxy) {
        val d = detector
        if (disposed || d == null) {
            imageProxy.close()
            return
        }
        d.detect(
            imageProxy,
            mirror = (lensFacing == CameraSelector.LENS_FACING_FRONT)
        )
    }

    // ---- Landmarker callbacks ----------------------------------------------

    private fun onResults(result: PoseLandmarkerResult, imageHeight: Int, imageWidth: Int) {
        if (result.landmarks().isEmpty()) {
            skeleton.clear()
        } else {
            skeleton.setResults(result, imageHeight, imageWidth)
        }
        if (!streaming) return

        // World landmarks (metres, hip-centred) for the angles; visibility
        // from the image landmarks of the same pose, as the scan uses.
        val world = result.worldLandmarks().firstOrNull()
        val image = result.landmarks().firstOrNull()
        val points = ArrayList<List<Double>>(33)
        if (world != null && image != null && world.size == 33 && image.size == 33) {
            for (i in 0 until 33) {
                val w = world[i]
                points.add(
                    listOf(
                        w.x().toDouble(),
                        w.y().toDouble(),
                        w.z().toDouble(),
                        image[i].visibility().orElse(0f).toDouble()
                    )
                )
            }
        }
        emit(
            mapOf(
                "timestampMs" to result.timestampMs(),
                "landmarks" to points,
                "body" to body(image, imageWidth, imageHeight)
            )
        )
    }

    /**
     * Where the body sits in the image, as [hipX, hipY, torso] in image
     * heights, so Flutter can tell walking about from exercising. Null unless
     * both shoulders and hips are clearly visible (the scan's 0.7 VIS_MIN):
     * guessed points jump about and would read as movement.
     */
    private fun body(
        image: List<com.google.mediapipe.tasks.components.containers.NormalizedLandmark>?,
        imageWidth: Int,
        imageHeight: Int
    ): List<Double>? {
        if (image == null || image.size != 33 || imageHeight <= 0) return null
        val ids = intArrayOf(11, 12, 23, 24) // shoulders, hips
        if (ids.any { image[it].visibility().orElse(0f) < 0.7f }) return null
        val aspect = imageWidth.toDouble() / imageHeight
        fun x(i: Int) = image[i].x() * aspect
        fun y(i: Int) = image[i].y().toDouble()
        val hipX = (x(23) + x(24)) / 2
        val hipY = (y(23) + y(24)) / 2
        val shoulderX = (x(11) + x(12)) / 2
        val shoulderY = (y(11) + y(12)) / 2
        val torso = Math.hypot(shoulderX - hipX, shoulderY - hipY)
        return if (torso > 0) listOf(hipX, hipY, torso) else null
    }

    private fun onError(error: String) {
        Log.e(TAG, "landmarker error: $error")
        // A GPU that accepted the model but fails on frames: carry on on the
        // CPU rather than leaving the counter silent.
        if (!disposed) executor.execute { detector?.fallBackToCpu() }
    }

    /** Event sinks must be touched on the main thread. */
    private fun emit(payload: Map<String, Any?>) {
        if (disposed) return
        ContextCompat.getMainExecutor(context).execute {
            if (!disposed) sink?.success(payload)
        }
    }

    // ---- Teardown -----------------------------------------------------------

    override fun dispose() {
        disposed = true
        streaming = false
        skeleton.clear()
        sink = null
        provider?.unbindAll()
        executor.execute { detector?.close() }
        executor.shutdown()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }
}

/**
 * MediaPipe Pose Landmarker set up for counting reps, where speed matters
 * more than the last bit of landmark precision. Separate from the scan's
 * PoseLandmarkerHelper so the measurement pipeline is unchanged.
 *
 * Differences from the scan (APP CHOICES, for speed):
 *  - the "lite" model when pose_landmarker_lite.task is in the app's assets,
 *    otherwise the same "full" model as the scan;
 *  - the GPU when the phone supports it, otherwise the CPU;
 *  - one person instead of two;
 *  - the camera frame's pixel buffer is reused instead of allocated anew
 *    for every frame.
 * Detection, tracking and presence confidence stay at the scan's 0.5.
 */
private class RepPoseDetector(
    private val context: Context,
    private val onResult: (PoseLandmarkerResult, Int, Int) -> Unit,
    private val onFailure: (String) -> Unit
) {
    companion object {
        private const val TAG = "AnthrofitPose"
        private const val LITE = "pose_landmarker_lite.task"
        private const val FULL = "pose_landmarker_full.task"
        private const val CONFIDENCE = 0.5f
    }

    private var landmarker: PoseLandmarker? = null
    private var model = FULL
    private var onGpu = false
    private var buffer: Bitmap? = null
    private var rotated: Bitmap? = null
    private var canvas: Canvas? = null
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)

    // Speed log: average time from frame to result, every 30 results.
    private var timedFrames = 0
    private var timedMs = 0L

    fun setUp() {
        model = if (hasAsset(LITE)) LITE else FULL
        landmarker = create(Delegate.GPU)
        onGpu = landmarker != null
        if (landmarker == null) landmarker = create(Delegate.CPU)
        Log.i(TAG, "rep counter: $model on ${if (onGpu) "GPU" else "CPU"}")
    }

    fun fallBackToCpu() {
        if (!onGpu) return
        landmarker?.close()
        onGpu = false
        landmarker = create(Delegate.CPU)
        Log.i(TAG, "rep counter: switched to CPU")
    }

    private fun hasAsset(name: String): Boolean =
        try {
            context.assets.list("")?.contains(name) == true
        } catch (e: Exception) {
            false
        }

    private fun create(delegate: Delegate): PoseLandmarker? =
        try {
            val base = BaseOptions.builder()
                .setModelAssetPath(model)
                .setDelegate(delegate)
                .build()
            val options = PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(base)
                .setRunningMode(RunningMode.LIVE_STREAM)
                .setNumPoses(1)
                .setMinPoseDetectionConfidence(CONFIDENCE)
                .setMinTrackingConfidence(CONFIDENCE)
                .setMinPosePresenceConfidence(CONFIDENCE)
                .setResultListener { result, input ->
                    logSpeed(result.timestampMs())
                    onResult(result, input.height, input.width)
                }
                .setErrorListener { e -> onFailure(e.message ?: "unknown error") }
                .build()
            PoseLandmarker.createFromOptions(context, options)
        } catch (e: Exception) {
            Log.w(TAG, "could not start the landmarker on $delegate", e)
            null
        }

    fun detect(imageProxy: ImageProxy, mirror: Boolean) {
        val lm = landmarker
        if (lm == null) {
            imageProxy.close()
            return
        }
        val width = imageProxy.width
        val height = imageProxy.height
        val rotation = imageProxy.imageInfo.rotationDegrees.toFloat()
        val source: Bitmap = buffer?.takeIf { it.width == width && it.height == height }
            ?: Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { buffer = it }
        imageProxy.use { source.copyPixelsFromBuffer(it.planes[0].buffer) }

        // Upright and, for the front camera, mirrored, exactly as the scan
        // does, so the skeleton overlay lines up with the preview.
        // Drawn into a reused bitmap: Bitmap.createBitmap(..., matrix, ...) made
        // a new 1.2 MB bitmap every frame, and the garbage collection that
        // followed delayed detection. MediaPipe copies the pixels in
        // detectAsync, so the bitmap can be overwritten on the next frame.
        val matrix = Matrix().apply {
            postRotate(rotation)
            if (mirror) postScale(-1f, 1f, width.toFloat(), height.toFloat())
        }
        val bounds = RectF(0f, 0f, width.toFloat(), height.toFloat())
        matrix.mapRect(bounds)
        matrix.postTranslate(-bounds.left, -bounds.top)
        val outW = bounds.width().roundToInt()
        val outH = bounds.height().roundToInt()
        val upright = rotated?.takeIf { it.width == outW && it.height == outH }
            ?: Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888).also {
                rotated = it
                canvas = Canvas(it)
            }
        canvas!!.drawBitmap(source, matrix, paint)
        lm.detectAsync(BitmapImageBuilder(upright).build(), SystemClock.uptimeMillis())
    }

    private fun logSpeed(frameTimeMs: Long) {
        timedMs += SystemClock.uptimeMillis() - frameTimeMs
        timedFrames++
        if (timedFrames == 30) {
            Log.i(TAG, "rep counter: ${timedMs / timedFrames} ms per frame ($model, ${if (onGpu) "GPU" else "CPU"})")
            timedFrames = 0
            timedMs = 0
        }
    }

    fun close() {
        landmarker?.close()
        landmarker = null
        buffer = null
        rotated = null
        canvas = null
    }
}
