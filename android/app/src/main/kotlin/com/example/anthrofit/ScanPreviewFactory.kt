package com.example.anthrofit

import android.content.Context
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
import com.google.mediapipe.tasks.vision.core.RunningMode
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors


/**
 * The camera preview Flutter embeds, plus the capture flow that runs behind it.
 *
 * Frames never cross the platform channel — only state updates and the final
 * measurement do. The Flutter side owns every pixel drawn on top of the
 * preview; this class owns the preview itself and all the measurement
 * decisions.
 */
class ScanPreviewFactory(
    private val messenger: BinaryMessenger,
    private val lifecycleOwner: () -> LifecycleOwner?
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    companion object {
        const val VIEW_TYPE = "anthrofit/scan_preview"
    }

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ScanPreview(context, viewId, messenger, lifecycleOwner)
}

class ScanPreview(
    private val context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    private val lifecycleOwner: () -> LifecycleOwner?
) : PlatformView, PoseLandmarkerHelper.LandmarkerListener {

    companion object {
        private const val TAG = "Anthrofit"
    }

    private val previewView = PreviewView(context).apply {
        scaleType = PreviewView.ScaleType.FILL_CENTER
    }
    private val skeleton = SkeletonOverlay(context)
    private val methods = MethodChannel(messenger, "anthrofit/scan_$viewId")
    private val events = EventChannel(messenger, "anthrofit/scan_events_$viewId")
    private var sink: EventChannel.EventSink? = null

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private var helper: PoseLandmarkerHelper? = null
    private var tilt: TiltMonitor? = null
    private var session: CaptureSession? = null
    private var provider: ProcessCameraProvider? = null
    private val container = FrameLayout(context).apply {
        addView(previewView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(skeleton, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    private var disposed = false

    private var lensFacing = CameraSelector.LENS_FACING_BACK

    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                this@ScanPreview.sink = sink
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })

        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> { startSession(); result.success(null) }
                "retry" -> { session?.start(); result.success(null) }
                "switchCamera" -> { switchCamera(); result.success(null) }
                else -> result.notImplemented()
            }
        }

        container.post { bindCamera() }
        startPipeline()
    }

    private fun switchCamera() {
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK) {
            CameraSelector.LENS_FACING_FRONT
        } else {
            CameraSelector.LENS_FACING_BACK
        }
        ContextCompat.getMainExecutor(context).execute {
            bindCamera()
        }
    }

    override fun getView(): View = container

    // ---- Pipeline -----------------------------------------------------------

    private fun startPipeline() {
        tilt = TiltMonitor(context).also { it.start() }

        executor.execute {
            helper = PoseLandmarkerHelper(
                context = context,
                runningMode = RunningMode.LIVE_STREAM,
                poseLandmarkerHelperListener = this
            ).also {
                it.tiltMonitor = tilt
            }
            Log.d(TAG, "helper ready, isClose=${helper?.isClose()}")
            startSession()
        }
    }

    private fun startSession() {
        val h = helper ?: return
        if (h == null) {
            Log.d(TAG, "startSession: helper null, bailing")
            return
        }
        Log.d(TAG, "startSession: creating session")
        val s = CaptureSession(object : CaptureSession.Listener {
            override fun onStateChanged(
                state: CaptureSession.State, message: String, holdProgress: Float
            ) {
                emit(
                    mapOf(
                        "phase" to phaseName(state),
                        "message" to message,
                        "holdProgress" to holdProgress.toDouble(),
                        // Frame counting is only meaningful while recording;
                        // the Flutter side shows the tape bar otherwise.
                        "framesCaptured" to
                                if (state == CaptureSession.State.RECORDING)
                                    (holdProgress * CaptureSession.FRAME_TARGET).toInt()
                                else 0,
                        "framesTotal" to CaptureSession.FRAME_TARGET
                    )
                )
            }

            override fun onCaptureComplete(result: Measurement.Aggregate) {
                Log.d(TAG, "capture complete: ${result.ratios}")
                emit(
                    mapOf(
                        "phase" to "done",
                        "message" to "Done",
                        "measurement" to measurementMap(result)
                    )
                )
            }

            override fun onCaptureFailed(reason: String) {
                Log.d(TAG, "capture failed: $reason")
                emit(mapOf("phase" to "failed", "message" to reason,
                    "failureReason" to reason))
            }
        })

        session = s
        h.captureSession = s
        s.start()
    }

    private fun phaseName(state: CaptureSession.State) = when (state) {
        CaptureSession.State.RECORDING -> "measuring"
        CaptureSession.State.HOLDING -> "holding"
        CaptureSession.State.DONE -> "done"
        else -> "guiding"
    }

    private fun measurementMap(r: Measurement.Aggregate): Map<String, Any> {
        val ratios = HashMap<String, Any>()
        r.ratios.forEach { (k, v) -> ratios[k] = v.toDouble() }

        val precision = HashMap<String, Any>()
        r.precision.forEach { (k, p) ->
            precision[k] = mapOf(
                "iqr" to p.iqr.toDouble(),
                "iqrPct" to p.iqrPct.toDouble(),
                "min" to p.min.toDouble(),
                "max" to p.max.toDouble()
            )
        }

        return mapOf(
            "takenAt" to System.currentTimeMillis(),
            "ratios" to ratios,
            "precision" to precision,
            "framesUsed" to r.framesUsed,
            "framesTotal" to r.framesTotal,
            "worstIqrPct" to r.worstIqrPct.toDouble(),
            "captureQuality" to r.captureQuality
        )
    }

    /// Event sinks must be touched on the main thread; the capture flow runs on
    /// the analysis executor.
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
                Log.e(TAG, "camera binding failed", e)
                emit(mapOf(
                    "phase" to "failed",
                    "message" to "Could not start the camera",
                    "failureReason" to "Could not start the camera"
                ))
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private var lastFrameMs = 0L
    private var frameCount = 0
    private var windowStartMs = 0L

    private fun detect(imageProxy: ImageProxy) {
        if (disposed) {
            imageProxy.close()
            return
        }
        val h = helper
        if (h == null) {
            Log.d(TAG, "frame dropped: helper not ready")
            imageProxy.close()
            return
        }

        val now = System.currentTimeMillis()
        if (windowStartMs == 0L) windowStartMs = now
        frameCount++
        if (now - windowStartMs >= 1000) {
            Log.d(TAG, "fps ${frameCount * 1000 / (now - windowStartMs)}")
            frameCount = 0
            windowStartMs = now
        }

        h.detectLiveStream(imageProxy, isFrontCamera = (lensFacing == CameraSelector.LENS_FACING_FRONT))
    }

    // ---- Landmarker callbacks ----------------------------------------------

    override fun onResults(resultBundle: PoseLandmarkerHelper.ResultBundle) {
        val result = resultBundle.results.firstOrNull() ?: return
        if (result.landmarks().isEmpty()) {
            // Without this the last skeleton stays frozen on screen after the
            // person walks away, which reads as the app having hung.
            skeleton.clear()
            return
        }
        skeleton.setResults(
            result,
            resultBundle.inputImageHeight,
            resultBundle.inputImageWidth
        )
    }

    override fun onError(error: String, errorCode: Int) {
        Log.e(TAG, "landmarker error: $error")
        emit(mapOf("phase" to "failed", "message" to error,
            "failureReason" to error))
    }

    // ---- Teardown -----------------------------------------------------------

    override fun dispose() {
        skeleton.clear()
        disposed = true
        sink = null
        tilt?.stop()
        session?.cancel()
        provider?.unbindAll()
        executor.execute { helper?.clearPoseLandmarker() }
        executor.shutdown()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }
}
