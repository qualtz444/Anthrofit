package com.example.anthrofit

import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Body proportion measurement.
 *
 * Port of measure_photo.py. Keep the two in step: the Python version is the
 * reference implementation used for batch processing and for checking this
 * one. Running the same image through both should give the same numbers.
 *
 * Two measurement bases, never mixed within one ratio:
 *   LANDMARK   - joint center to joint center. Primary basis.
 *   SILHOUETTE - body surface, from the segmentation mask. Recorded in
 *                parallel for comparison, and the only possible source for
 *                chest and waist, which have no landmark equivalent.
 */
object Measurement {

    // ---- BlazePose landmark indices ----
    private const val NOSE = 0
    private const val L_SHOULDER = 11
    private const val R_SHOULDER = 12
    private const val L_ELBOW = 13
    private const val R_ELBOW = 14
    private const val L_WRIST = 15
    private const val R_WRIST = 16
    private const val L_HIP = 23
    private const val R_HIP = 24
    private const val L_KNEE = 25
    private const val R_KNEE = 26
    private const val L_ANKLE = 27
    private const val R_ANKLE = 28

    private val REQUIRED = intArrayOf(
        L_SHOULDER, R_SHOULDER, L_HIP, R_HIP, L_ELBOW, R_ELBOW,
        L_WRIST, R_WRIST, L_KNEE, R_KNEE, L_ANKLE, R_ANKLE
    )

    // ---- Acceptance thresholds ----
    // These mirror measure_photo.py. Keep the two in step.
    //
    // Blur, exposure and clipping are NOT checked here: they need the raw
    // image rather than landmarks, so they live in the camera layer. See
    // PoseLandmarkerHelper.checkFrameQuality.
    const val VIS_MIN = 0.7f
    const val ROTATION_TOL = 0.15f
    const val MASK_THRESH = 0.5f
    private const val ARM_MERGE_FACTOR = 1.5f

    // Arm abduction, in degrees from straight down.
    //
    // This range is not arbitrary. Testing showed both ends fail:
    //   arms at the sides (~0 deg)  - the silhouette at hip level spans
    //       forearm|torso|forearm as one run, overestimating hip width by 131%
    //   T-pose (~90 deg)            - the row through the shoulders runs the
    //       full arm span, so shoulder width becomes arm span
    // Between roughly 15 and 40 degrees there is a clear gap beside the trunk
    // at hip level while the arms still slope away from the shoulder line.
    //
    // The check uses an angle rather than a distance because angles are
    // scale-invariant: the same pose passes whether the subject stands 2 m or
    // 4 m from the camera.
    const val ARM_ANGLE_MIN = 15f
    const val ARM_ANGLE_MAX = 40f

    data class Ratios(
        val lmShoulderHip: Float?,
        val armTorso: Float?,
        val femurTorso: Float?,
        val upperbodyStature: Float?,
        val silShoulderHip: Float?,
        val silWaistHip: Float?,
        val silWaistChest: Float?
    ) {
        fun asMap(): Map<String, Float> = buildMap {
            lmShoulderHip?.let { put("lm_shoulder_hip_ratio", it) }
            armTorso?.let { put("arm_torso_ratio", it) }
            femurTorso?.let { put("femur_torso_ratio", it) }
            upperbodyStature?.let { put("upperbody_stature_ratio", it) }
            silShoulderHip?.let { put("sil_shoulder_hip_ratio", it) }
            silWaistHip?.let { put("sil_waist_hip_ratio", it) }
            silWaistChest?.let { put("sil_waist_chest_ratio", it) }
        }
    }

    sealed class Result {
        data class Ok(
            val ratios: Ratios,
            val landmarkPx: Map<String, Float>,
            val silhouettePx: Map<String, Int>,
            val measuredAtY: Map<String, Int>,
            val siteFractionOfTorso: Map<String, Float>
        ) : Result()

        data class Rejected(val reason: String) : Result()
    }

    // -----------------------------------------------------------------------
    // Silhouette helpers
    // -----------------------------------------------------------------------

    /** Contiguous true runs in one mask row, as [start, end] index pairs. */
    fun runsInRow(row: BooleanArray): List<IntArray> {
        val runs = mutableListOf<IntArray>()
        var start = -1
        for (i in row.indices) {
            if (row[i] && start < 0) start = i
            else if (!row[i] && start >= 0) {
                runs.add(intArrayOf(start, i - 1)); start = -1
            }
        }
        if (start >= 0) runs.add(intArrayOf(start, row.size - 1))
        return runs
    }

    /**
     * Torso width at row y, in pixels.
     *
     * With the arms abducted, a row through the hips contains three runs:
     * left arm | torso | right arm. Taking the full left-to-right extent
     * measures across the forearms - in testing this overestimated hip width
     * by 131%. We take the run containing the body midline instead.
     */
    fun torsoWidthAt(mask: Array<BooleanArray>, y: Int, centerX: Int): Pair<Int, IntArray>? {
        if (y < 0 || y >= mask.size) return null
        val runs = runsInRow(mask[y])
        if (runs.isEmpty()) return null

        runs.firstOrNull { centerX >= it[0] && centerX <= it[1] }?.let {
            return Pair(it[1] - it[0] + 1, it)
        }
        // Midline fell in a gap: use the run nearest to it.
        val near = runs.minByOrNull { abs((it[0] + it[1]) / 2.0 - centerX) }!!
        return Pair(near[1] - near[0] + 1, near)
    }

    /**
     * Scan a row range and return the widest (pickMax) or narrowest run.
     * The landmarks give the search RANGE; the silhouette decides the exact
     * row. A fixed row moves whenever the landmarks wobble, and the torso
     * tapers quickly, so small landmark noise became several percent of width.
     */
    private fun scan(
        mask: Array<BooleanArray>, y0: Int, y1: Int, centerX: Int, pickMax: Boolean
    ): Triple<Int, Int, IntArray>? {
        var best: Triple<Int, Int, IntArray>? = null
        for (y in y0.coerceAtLeast(0) until y1.coerceAtMost(mask.size)) {
            val r = torsoWidthAt(mask, y, centerX) ?: continue
            val cand = Triple(r.first, y, r.second)
            val b = best
            if (b == null ||
                (pickMax && cand.first > b.first) ||
                (!pickMax && cand.first < b.first)
            ) best = cand
        }
        return best
    }

    /**
     * Angle of the shoulder-to-wrist vector away from straight down, in
     * degrees. 0 = arm hanging vertically, 90 = arm horizontal (T-pose).
     *
     * Only the magnitude of the horizontal component matters, so the left and
     * right sides give comparable numbers without sign handling.
     */
    private fun abductionDegrees(shoulder: FloatArray, wrist: FloatArray): Float {
        val dx = abs(wrist[0] - shoulder[0])
        val dy = wrist[1] - shoulder[1]          // positive = wrist below shoulder
        if (dy <= 0f) return 90f                 // wrist at or above shoulder height
        return Math.toDegrees(atan2(dx, dy).toDouble()).toFloat()
    }

    // -----------------------------------------------------------------------
    // Measurement
    // -----------------------------------------------------------------------

    /**
     * @param lm 33 normalized landmarks from PoseLandmarker
     * @param mask segmentation mask, already thresholded, indexed [row][column]
     * @param w frame width in pixels
     * @param h frame height in pixels
     */
    fun measure(
        lm: List<NormalizedLandmark>,
        mask: Array<BooleanArray>?,
        w: Int,
        h: Int,
        detectedPoses: Int = 1
    ): Result {
        // Mirrors and other gym occupants produce extra detections. Measuring
        // the wrong person, or a reflection, is worse than failing the frame.
        if (detectedPoses > 1)
            return Result.Rejected("more than one person in frame")

        if (lm.size < 33) return Result.Rejected("incomplete landmark set")

        // Landmark confidence
        val weak = REQUIRED.filter { (lm[it].visibility().orElse(0f)) < VIS_MIN }
        if (weak.isNotEmpty())
            return Result.Rejected("low landmark visibility at ${weak.size} required points")

        fun px(i: Int) = floatArrayOf(lm[i].x() * w, lm[i].y() * h)
        fun dist(a: FloatArray, b: FloatArray): Float {
            val dx = a[0] - b[0]; val dy = a[1] - b[1]
            return sqrt(dx * dx + dy * dy)
        }

        val ls = px(L_SHOULDER); val rs = px(R_SHOULDER)
        val lh = px(L_HIP); val rh = px(R_HIP)

        // Full body in frame
        if (lm[NOSE].y() < 0.02f || REQUIRED.any { lm[it].y() > 0.98f })
            return Result.Rejected("full body not inside frame")

        // Rotation: compare left and right half widths about the midline
        val midX = (ls[0] + rs[0] + lh[0] + rh[0]) / 4f
        val leftHalf = abs(maxOf(ls[0], lh[0]) - midX)
        val rightHalf = abs(midX - minOf(rs[0], rh[0]))
        val imbalance = abs(leftHalf - rightHalf) / maxOf(leftHalf, rightHalf, 1e-6f)
        if (imbalance > ROTATION_TOL)
            return Result.Rejected("subject not square to camera")

        // Arm abduction: angle of the shoulder-to-wrist vector away from
        // straight down. Averaged across both sides so a single mislocated
        // wrist does not decide the outcome.
        val leftArmDeg = abductionDegrees(ls, px(L_WRIST))
        val rightArmDeg = abductionDegrees(rs, px(R_WRIST))
        val armDeg = (leftArmDeg + rightArmDeg) / 2f
        if (armDeg < ARM_ANGLE_MIN)
            return Result.Rejected(
                "arms too close to the body (${armDeg.roundToInt()} deg) - " +
                        "move your arms further from your sides"
            )
        if (armDeg > ARM_ANGLE_MAX)
            return Result.Rejected(
                "arms raised too high (${armDeg.roundToInt()} deg) - " +
                        "lower your arms closer to your sides"
            )

        // ---- Landmark measurements (primary basis) ----
        val lmShoulderW = abs(ls[0] - rs[0])
        val lmHipW = abs(lh[0] - rh[0])

        val torsoLen = (dist(ls, lh) + dist(rs, rh)) / 2f
        val armLen = (dist(ls, px(L_ELBOW)) + dist(px(L_ELBOW), px(L_WRIST)) +
                dist(rs, px(R_ELBOW)) + dist(px(R_ELBOW), px(R_WRIST))) / 2f
        val femurLen = (dist(lh, px(L_KNEE)) + dist(rh, px(R_KNEE))) / 2f

        val shoulderLmY = (ls[1] + rs[1]) / 2f
        val hipY = (lh[1] + rh[1]) / 2f
        val headY = lm[NOSE].y() * h
        val ankleY = (px(L_ANKLE)[1] + px(R_ANKLE)[1]) / 2f
        val stature = ankleY - headY
        val upperBody = hipY - headY

        if (torsoLen <= 0f || stature <= 0f || lmHipW <= 0f)
            return Result.Rejected("degenerate landmark geometry")

        // ---- Silhouette measurements (parallel, exploratory) ----
        var silShoulder: Int? = null; var silChest: Int? = null
        var silWaist: Int? = null; var silHip: Int? = null
        var shoulderY = shoulderLmY.roundToInt()
        var chestY = 0; var waistY = 0; var hipSilY = 0

        if (mask != null) {
            val torso = hipY - shoulderLmY
            val cx = midX.roundToInt()

            // Shoulder: widest row in the top 30% of the torso. The landmark
            // row sits on the trapezius, above the deltoids, and read narrow
            // against a tape taken at the widest point.
            scan(mask, shoulderLmY.toInt(), (shoulderLmY + 0.30f * torso).toInt(), cx, true)
                ?.let { silShoulder = it.first; shoulderY = it.second }

            // Chest: widest row, 20-45% of torso. Scott's stable-landmark
            // proportions place the chest at 37.5% (Zong et al. 2023).
            scan(mask, (shoulderLmY + 0.20f * torso).toInt(),
                (shoulderLmY + 0.45f * torso).toInt(), cx, true)
                ?.let { silChest = it.first; chestY = it.second }

            // Waist: narrowest row, 45-85%. Scott places the waistline at 62.5%.
            scan(mask, (shoulderLmY + 0.45f * torso).toInt(),
                (shoulderLmY + 0.85f * torso).toInt(), cx, false)
                ?.let { silWaist = it.first; waistY = it.second }

            // Hip: widest row, 85-115%.
            scan(mask, (shoulderLmY + 0.85f * torso).toInt(),
                (shoulderLmY + 1.15f * torso).toInt(), cx, true)
                ?.let { silHip = it.first; hipSilY = it.second }

            // Guard: forearms merged into the torso inflate the silhouette.
            listOf("shoulder" to silShoulder, "chest" to silChest,
                "waist" to silWaist, "hip" to silHip).forEach { (name, v) ->
                if (v != null && v > ARM_MERGE_FACTOR * lmShoulderW)
                    return Result.Rejected(
                        "$name measurement includes the arms (${v}px vs shoulder " +
                                "span ${lmShoulderW.roundToInt()}px) - increase arm abduction"
                    )
            }
        }

        val sSh = silShoulder; val sCh = silChest
        val sWa = silWaist; val sHi = silHip

        val ratios = Ratios(
            lmShoulderHip = lmShoulderW / lmHipW,
            armTorso = armLen / torsoLen,
            femurTorso = femurLen / torsoLen,
            upperbodyStature = upperBody / stature,
            silShoulderHip = if (sSh != null && sHi != null) sSh.toFloat() / sHi else null,
            silWaistHip = if (sWa != null && sHi != null) sWa.toFloat() / sHi else null,
            silWaistChest = if (sWa != null && sCh != null) sWa.toFloat() / sCh else null
        )

        val torso = hipY - shoulderLmY
        return Result.Ok(
            ratios = ratios,
            landmarkPx = mapOf(
                "shoulder" to lmShoulderW, "hip" to lmHipW,
                "torso_len" to torsoLen, "arm_len" to armLen, "femur_len" to femurLen
            ),
            silhouettePx = buildMap {
                sSh?.let { put("shoulder", it) }
                sCh?.let { put("chest", it) }
                sWa?.let { put("waist", it) }
                sHi?.let { put("hip", it) }
            },
            measuredAtY = mapOf(
                "shoulder" to shoulderY, "chest" to chestY,
                "waist" to waistY, "hip" to hipSilY,
                "shoulder_lm" to shoulderLmY.roundToInt(), "hip_lm" to hipY.roundToInt()
            ),
            siteFractionOfTorso = if (torso > 0) mapOf(
                "chest" to (chestY - shoulderLmY) / torso,
                "waist" to (waistY - shoulderLmY) / torso
            ) else emptyMap()
        )
    }

    // -----------------------------------------------------------------------
    // Multi-frame aggregation
    // -----------------------------------------------------------------------

    data class Aggregate(
        val ratios: Map<String, Float>,
        val precision: Map<String, Precision>,
        val framesUsed: Int,
        val framesTotal: Int,
        val worstIqrPct: Float,
        val captureQuality: String
    )

    data class Precision(val iqr: Float, val iqrPct: Float, val min: Float, val max: Float)

    /**
     * Median across frames, not mean: one badly-detected frame shifts a mean
     * but leaves a median almost untouched. The interquartile range is kept as
     * a precision indicator and doubles as a within-session repeatability
     * statistic (Chapter 3, Stage 8).
     */
    fun aggregate(frames: List<Result>, minAccepted: Int = 5): Aggregate? {
        val ok = frames.filterIsInstance<Result.Ok>()
        if (ok.size < minAccepted) return null

        val ratios = mutableMapOf<String, Float>()
        val precision = mutableMapOf<String, Precision>()

        val keys = ok.first().ratios.asMap().keys
        for (k in keys) {
            val vals = ok.mapNotNull { it.ratios.asMap()[k] }.sorted()
            if (vals.isEmpty()) continue
            val n = vals.size
            val med = if (n % 2 == 1) vals[n / 2] else (vals[n / 2 - 1] + vals[n / 2]) / 2f
            val q1 = vals[(0.25 * (n - 1)).toInt()]
            val q3 = vals[(0.75 * (n - 1)).toInt()]
            ratios[k] = med
            precision[k] = Precision(
                iqr = q3 - q1,
                iqrPct = if (med != 0f) 100f * (q3 - q1) / med else 0f,
                min = vals.first(), max = vals.last()
            )
        }

        val worst = precision.values.maxOfOrNull { it.iqrPct } ?: 0f
        return Aggregate(
            ratios = ratios,
            precision = precision,
            framesUsed = ok.size,
            framesTotal = frames.size,
            worstIqrPct = worst,
            captureQuality = when {
                worst < 2f -> "good"
                worst < 5f -> "acceptable"
                else -> "unstable"
            }
        )
    }
}