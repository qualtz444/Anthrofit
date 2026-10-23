package com.example.anthrofit.composition

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
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
import com.example.anthrofit.TiltMonitor
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.ByteBufferExtractor
import com.google.mediapipe.framework.image.MPImage
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
import java.io.ByteArrayOutputStream
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Camera preview and capture for BODY COMPOSITION.
 *
 * A separate platform view from the body-proportion scan, on purpose. It runs
 * its own Pose Landmarker with segmentation masks switched on, so the
 * validated proportion pipeline (PoseLandmarkerHelper, CaptureSession,
 * Measurement) is untouched and its acquisition conditions do not change.
 *
 * Flutter contract
 *   view type   anthrofit/composition_preview
 *   methods     anthrofit/composition_<id>          start, retry
 *   events      anthrofit/composition_events_<id>
 *
 * Events are maps:
 *   progress  { phase: positioning|holding|confirmed, step: front|side,
 *               stepIndex: 0|1, stepCount: 2, title, message, holdProgress }
 *   done      { phase: done, front: [mask...], side: [mask...],
 *               frontPhoto: jpeg?, sidePhoto: jpeg? }
 *             each mask is the Int32List from MaskOps.encodeRuns; the photos
 *             are only sent when created with includePhotos = true
 *
 * Creation params: { includePhotos: bool } (default false)
 *   failed    { phase: failed, message, failureReason }
 */
class CompositionPreviewFactory(
    private val messenger: BinaryMessenger,
    private val lifecycleOwner: () -> LifecycleOwner?,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    companion object {
        const val VIEW_TYPE = "anthrofit/composition_preview"
    }

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val includePhotos = (args as? Map<*, *>)?.get("includePhotos") == true
        return CompositionPreview(context, viewId, messenger, lifecycleOwner, includePhotos)
    }
}

class CompositionPreview(
    private val context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    private val lifecycleOwner: () -> LifecycleOwner?,
    /** Whether to keep a front and side photo on the phone. */
    private val includePhotos: Boolean = false,
) : PlatformView, SilhouetteCapture.Listener {

    private companion object {
        const val TAG = "AnthrofitComposition"
        const val MODEL = "pose_landmarker_full.task"

        /** JPEG quality for the saved camera frame. */
        const val PHOTO_QUALITY = 85
    }

    private val previewView = PreviewView(context).apply {
        scaleType = PreviewView.ScaleType.FILL_CENTER
    }
    private val container = FrameLayout(context).apply {
        addView(previewView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }
    private val methods = MethodChannel(messenger, "anthrofit/composition_$viewId")
    private val events = EventChannel(messenger, "anthrofit/composition_events_$viewId")
    private var sink: EventChannel.EventSink? = null

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private var landmarker: PoseLandmarker? = null
    private var tilt: TiltMonitor? = null
    private var capture: SilhouetteCapture? = null
    private var provider: ProcessCameraProvider? = null
    private val photoFrames = ConcurrentHashMap<Long, Bitmap>()
    private val photoInferenceInFlight = AtomicBoolean(false)

    @Volatile private var disposed = false

    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                this@CompositionPreview.sink = sink
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })

        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "start", "retry" -> { executor.execute { capture?.start() }; result.success(null) }
                else -> result.notImplemented()
            }
        }

        tilt = TiltMonitor(context).also { it.start() }
        executor.execute { setUpPipeline() }
        container.post { bindCamera() }
    }

    override fun getView(): View = container

    // ---- Pipeline -----------------------------------------------------------

    private fun setUpPipeline() {
        capture = SilhouetteCapture({ SystemClock.uptimeMillis() }, this)
        try {
            val options = PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(
                    BaseOptions.builder()
                        .setModelAssetPath(MODEL)
                        .setDelegate(Delegate.CPU)
                        .build()
                )
                .setRunningMode(RunningMode.LIVE_STREAM)
                // Two, so a mirror reflection or a bystander is seen and the
                // frame refused, rather than silently measuring the wrong person.
                .setNumPoses(2)
                .setMinPoseDetectionConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .setMinPosePresenceConfidence(0.5f)
                // The point of this view: a per-pixel person confidence mask.
                .setOutputSegmentationMasks(true)
                .setResultListener { result, image -> onResult(result, image) }
                .setErrorListener { e ->
                    photoFrames.clear()
                    photoInferenceInFlight.set(false)
                    fail(e.message ?: "Pose detection failed")
                }
                .build()
            landmarker = PoseLandmarker.createFromOptions(context, options)
            capture?.start()
        } catch (e: Exception) {
            Log.e(TAG, "landmarker failed to start", e)
            fail("Could not start body detection")
        }
    }

    private fun onResult(result: PoseLandmarkerResult, image: MPImage) {
        try {
            onResultData(result, image)
        } finally {
            photoFrames.remove(result.timestampMs())
            if (includePhotos && photoFrames.isNotEmpty()) {
                Log.w(TAG, "Discarding unmatched camera frame")
                photoFrames.clear()
            }
            if (includePhotos) photoInferenceInFlight.set(false)
        }
    }

    private fun onResultData(result: PoseLandmarkerResult, image: MPImage) {
        val cap = capture ?: return
        val w = image.width
        val h = image.height
        val poses = result.landmarks().size
        val deviceIssue = tilt?.checkOrNull()?.let { "Stand the phone up straight." }

        if (poses == 0) {
            cap.onFrame(SilhouetteCapture.FrameInput(null, 0, null, w, h, deviceIssue))
            return
        }

        // This bitmap is copied from the camera frame before it enters MediaPipe.
        // Only the selected frame is encoded and persisted as the original photo.
        val photoBitmap = if (includePhotos) {
            photoFrames.remove(result.timestampMs())
        } else null
        if (includePhotos && photoBitmap == null) {
            Log.w(TAG, "No camera frame matched pose result ${result.timestampMs()}")
        }
        val photo: (() -> ByteArray)? = photoBitmap?.let { bitmap ->
            ({ jpegOf(bitmap) })
        }

        val landmarks = result.landmarks()[0].map {
            Landmark(it.x(), it.y(), it.z(), it.visibility().orElse(0f))
        }

        // The mask list lines up with the pose list; take the first pose's.
        val mask = result.segmentationMasks().orElse(null)?.firstOrNull()
        val confidence: FloatArray? = mask?.let { floatsOf(it, w, h) }

        cap.onFrame(
            SilhouetteCapture.FrameInput(landmarks, poses, confidence, w, h, deviceIssue, photo)
        )
    }

    /** A color JPEG of the camera frame, separate from the silhouette mask. */
    private fun jpegOf(bitmap: Bitmap): ByteArray {
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, PHOTO_QUALITY, out)
        return out.toByteArray()
    }

    /** The mask is a float32 image the size of the input frame. */
    private fun floatsOf(mask: MPImage, w: Int, h: Int): FloatArray? {
        if (mask.width != w || mask.height != h) return null
        val buffer = ByteBufferExtractor.extract(mask).order(ByteOrder.nativeOrder())
        val floats = buffer.asFloatBuffer()
        if (floats.remaining() < w * h) return null
        val out = FloatArray(w * h)
        floats.get(out, 0, w * h)
        return out
    }

    // ---- Capture callbacks (called on the analysis thread) -------------------

    override fun onProgress(progress: SilhouetteCapture.Progress) {
        emit(
            mapOf(
                "phase" to when (progress.phase) {
                    SilhouetteCapture.Phase.HOLDING -> "holding"
                    SilhouetteCapture.Phase.CONFIRMED -> "confirmed"
                    else -> "positioning"
                },
                "step" to progress.step.id,
                "stepIndex" to progress.step.ordinal,
                "stepCount" to SilhouetteCapture.Step.values().size,
                "title" to progress.step.title,
                "message" to progress.message,
                "holdProgress" to progress.holdProgress.toDouble(),
            )
        )
    }

    override fun onComplete(
        front: List<SilhouetteCapture.Frame>,
        side: List<SilhouetteCapture.Frame>,
    ) {
        fun encode(frames: List<SilhouetteCapture.Frame>) =
            frames.map { MaskOps.encodeRuns(it.mask, it.width, it.height) }
        emit(
            mapOf(
                "phase" to "done",
                "front" to encode(front),
                "side" to encode(side),
                "frontPhoto" to front.firstOrNull()?.photo,
                "sidePhoto" to side.firstOrNull()?.photo,
            )
        )
    }

    override fun onFailed(reason: String) = fail(reason)

    private fun fail(reason: String) {
        emit(mapOf("phase" to "failed", "message" to reason, "failureReason" to reason))
    }

    /** Event sinks must be touched on the main thread. */
    private fun emit(payload: Map<String, Any?>) {
        if (disposed) return
        ContextCompat.getMainExecutor(context).execute {
            if (!disposed) sink?.success(payload)
        }
    }

    // ---- Camera -------------------------------------------------------------

    private fun bindCamera() {
        val owner = lifecycleOwner() ?: run {
            Log.e(TAG, "no lifecycle owner; cannot bind camera")
            return
        }
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            provider = future.get()
            // Rear camera only: the person stands back from a propped phone.
            val selector = CameraSelector.Builder()
                .requireLensFacing(CameraSelector.LENS_FACING_BACK)
                .build()

            val preview = Preview.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .build()

            val analyzer = ImageAnalysis.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                .build()
                .also { it.setAnalyzer(executor) { image -> analyse(image) } }

            try {
                provider?.unbindAll()
                provider?.bindToLifecycle(owner, selector, preview, analyzer)
                preview.setSurfaceProvider(previewView.surfaceProvider)
            } catch (e: Exception) {
                Log.e(TAG, "camera binding failed", e)
                fail("Could not start the camera")
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun analyse(imageProxy: ImageProxy) {
        val lm = landmarker
        if (disposed || lm == null) {
            imageProxy.close()
            return
        }
        // Keep the source bitmap paired with its asynchronous pose result.
        if (includePhotos && !photoInferenceInFlight.compareAndSet(false, true)) {
            imageProxy.close()
            return
        }

        val frameTime = SystemClock.uptimeMillis()
        try {
            val rotation = imageProxy.imageInfo.rotationDegrees.toFloat()
            // toBitmap() honours the row stride. A raw buffer copy does not,
            // and on phones that pad each row the frame (and so the outline)
            // shears.
            val bitmap = imageProxy.use { it.toBitmap() }

            // Rotate to the way the person is standing, so the mask's rows
            // run head to foot.
            val upright = Bitmap.createBitmap(
                bitmap, 0, 0, bitmap.width, bitmap.height,
                Matrix().apply { postRotate(rotation) }, true
            )
            if (includePhotos) {
                val photoFrame = upright.copy(Bitmap.Config.ARGB_8888, false)
                if (photoFrame == null) {
                    Log.w(TAG, "Could not retain the original camera frame")
                } else {
                    photoFrames[frameTime] = photoFrame
                }
            }
            lm.detectAsync(BitmapImageBuilder(upright).build(), frameTime)
        } catch (e: RuntimeException) {
            photoFrames.remove(frameTime)
            if (includePhotos) photoInferenceInFlight.set(false)
            Log.e(TAG, "frame analysis failed", e)
            fail("Could not process the camera frame")
        }
    }

    // ---- Teardown -----------------------------------------------------------

    override fun dispose() {
        disposed = true
        sink = null
        photoFrames.clear()
        tilt?.stop()
        capture?.cancel()
        provider?.unbindAll()
        executor.execute {
            landmarker?.close()
            landmarker = null
        }
        executor.shutdown()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }
}
