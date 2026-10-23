package com.example.anthrofit

import io.flutter.embedding.android.FlutterActivity
import com.example.anthrofit.composition.CompositionPreviewFactory
import io.flutter.embedding.engine.FlutterEngine

/**
 * Flutter host.
 *
 * Registers the camera preview as a platform view. Everything else — starting
 * a scan, guidance updates, the finished measurement — flows through the
 * per-view channels that ScanPreview sets up, so there is nothing to wire here
 * beyond the registration itself.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                ScanPreviewFactory.VIEW_TYPE,
                ScanPreviewFactory(
                    flutterEngine.dartExecutor.binaryMessenger,
                    // CameraX needs a LifecycleOwner. Passed lazily because the
                    // factory outlives any single view, and the activity may be
                    // gone by the time a late frame arrives.
                    lifecycleOwner = { this }
                )
            )

        // Body composition has its own camera view, kept apart from the scan
        // above so the proportion pipeline is not touched.
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                CompositionPreviewFactory.VIEW_TYPE,
                CompositionPreviewFactory(
                    flutterEngine.dartExecutor.binaryMessenger,
                    lifecycleOwner = { this }
                )
            )

        // Live pose stream for the guided set's rep counter. Its own view, so
        // neither scan pipeline is touched.
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                PosePreviewFactory.VIEW_TYPE,
                PosePreviewFactory(
                    flutterEngine.dartExecutor.binaryMessenger,
                    lifecycleOwner = { this }
                )
            )
    }
}