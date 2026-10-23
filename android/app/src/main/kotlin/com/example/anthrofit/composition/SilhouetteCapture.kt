package com.example.anthrofit.composition

/**
 * Walks the user through the two positions body composition needs, front then
 * side, and keeps the best few silhouettes from each.
 *
 * Why two confirmed positions rather than one blind sweep: people are bad at
 * judging a 90 degree turn, so the app checks the turn happened. Bad frames
 * are discarded during capture rather than rejected afterwards, and several
 * good frames per position let segmentation noise average out. (That removes
 * only random error; the model's systematic bias is untouched.)
 *
 * Ported from the bodycomp project's scan.js (MIT). Pure Kotlin: time comes
 * from an injected clock and frames arrive through [onFrame], so the whole
 * flow is tested without a camera.
 *
 * This is a separate capture from the body-proportion scan on purpose. It
 * never touches CaptureSession or Measurement, so the validated proportion
 * pipeline and its acquisition conditions are unchanged.
 */
class SilhouetteCapture(
    private val clock: () -> Long,
    private val listener: Listener,
) {

    companion object {
        /** Best frames kept per position. */
        const val KEEP_PER_VIEW = 3

        /** Time in position before the frames are banked. */
        const val HOLD_MS = 1200L

        /** How long the "captured" confirmation stays up between positions. */
        const val CONFIRM_MS = 900L

        /** Sustained time out of position before the hold restarts. */
        const val BAD_RESET_MS = 900L

        /** A gap longer than this (app backgrounded) is not counted as time. */
        const val MAX_DT_MS = 250L

        /** Give up on one position after this long without finishing it. */
        const val STEP_TIMEOUT_MS = 60_000L

        /** Weight of the newest landmark positions in the smoothing. */
        const val SMOOTH = 0.4f

        /** Dropped detections tolerated before the position is treated as lost. */
        const val NO_POSE_GRACE = 6

        /** Shoulder span / body height. Square on is about 0.20-0.26. */
        const val FRONT_SPAN_MIN = 0.13f

        /** The same measure in profile, used if the front step gave no reference. */
        const val SIDE_SPAN_MAX = 0.11f

        /** A side view sits below this share of this person's own front span. */
        const val SIDE_DROP = 0.62f
    }

    enum class Step(
        val id: String,
        val title: String,
        val detail: String,
        val facing: Boolean,
    ) {
        FRONT(
            "front",
            "Face the camera",
            "Stand square on, arms out about 30 degrees from your body.",
            true,
        ),
        SIDE(
            "side",
            "Turn 90 degrees to your right",
            "One shoulder to the camera, arms relaxed at your sides.",
            false,
        ),
    }

    enum class Phase { IDLE, POSITIONING, HOLDING, CONFIRMED, DONE, FAILED }

    /**
     * One silhouette, cleaned, ready to send. [photo] is a JPEG of the camera
     * frame it came from, only for the best frame of a view.
     */
    class Frame(
        val width: Int,
        val height: Int,
        val mask: ByteArray,
        val photo: ByteArray? = null,
    )

    /** One incoming camera frame, already through the pose and segmentation models. */
    class FrameInput(
        /** The first (most confident) pose's landmarks, or null when none. */
        val landmarks: List<Landmark>?,
        /** How many people the pose model found. */
        val poseCount: Int,
        /** Person confidence for the first pose, row-major, or null. */
        val confidence: FloatArray?,
        val width: Int,
        val height: Int,
        /** Set when the phone is not upright, from the accelerometer. */
        val deviceIssue: String? = null,
        /**
         * Makes a JPEG of this frame, or null when photos are off. A function
         * so nothing is encoded unless the frame ends up being kept, and so
         * this class stays free of Android types.
         */
        val photo: (() -> ByteArray)? = null,
    )

    class Progress(
        val phase: Phase,
        val step: Step,
        val message: String,
        /** 0..1 through the hold at the current position. */
        val holdProgress: Float,
    )

    interface Listener {
        fun onProgress(progress: Progress)
        fun onComplete(front: List<Frame>, side: List<Frame>)
        fun onFailed(reason: String)
    }

    var phase: Phase = Phase.IDLE
        private set

    var step: Step = Step.FRONT
        private set

    private class Candidate(
        val score: Float,
        val spanRatio: Float,
        val width: Int,
        val height: Int,
        val raw: ByteArray,
        val landmarks: List<Landmark>,
        val photo: (() -> ByteArray)?,
    )

    private var holdMs = 0L
    private var badMs = 0L
    private var lastTick = 0L
    private var noPose = 0
    private var stepStart = 0L
    private var confirmUntil = 0L
    private var smoothed: Array<FloatArray>? = null
    private var best = ArrayList<Candidate>()
    private var frontSpan = 0f
    private var lastIssue = ""
    private val issueCounts = HashMap<String, Int>()
    private val front = ArrayList<Frame>()

    @Synchronized
    fun start() {
        step = Step.FRONT
        frontSpan = 0f
        front.clear()
        resetStep()
        phase = Phase.POSITIONING
        report(step.detail, 0f)
    }

    @Synchronized
    fun cancel() {
        phase = Phase.IDLE
        best.clear()
    }

    private fun resetStep() {
        holdMs = 0
        badMs = 0
        lastTick = 0
        noPose = 0
        stepStart = clock()
        smoothed = null
        best = ArrayList()
        issueCounts.clear()
    }

    private fun report(message: String, hold: Float) {
        lastIssue = message
        listener.onProgress(Progress(phase, step, message, hold.coerceIn(0f, 1f)))
    }

    /** Does this frame's shoulder span fit the position being asked for? */
    private fun matches(a: ViewAssessment.Assessment): Boolean {
        val span = a.spanRatio
        return when (step) {
            Step.FRONT -> span > FRONT_SPAN_MIN
            Step.SIDE -> {
                val limit = if (frontSpan > 0f) frontSpan * SIDE_DROP else SIDE_SPAN_MAX
                span < limit
            }
        }
    }

    private fun wrongMessage(): String = when (step) {
        Step.FRONT -> "Turn to face the camera square on."
        Step.SIDE -> "Keep turning until one shoulder faces the camera."
    }

    /** Front wants wide, level shoulders; side wants the narrowest. */
    private fun score(a: ViewAssessment.Assessment): Float = when (step) {
        Step.FRONT -> a.ratio - 2 * a.tilt
        Step.SIDE -> -a.ratio + 0.5f * a.minVisibility
    }

    /**
     * Exponential smoothing of landmark positions. Raw pose output jitters
     * frame to frame, and every measure here inherits the jitter; smoothing
     * once fixes all of them.
     */
    private fun smooth(lm: List<Landmark>): List<Landmark> {
        val prev = smoothed
        if (prev == null || prev.size != lm.size) {
            smoothed = Array(lm.size) { floatArrayOf(lm[it].x, lm[it].y, lm[it].z, lm[it].visibility) }
        } else {
            for (i in lm.indices) {
                val e = prev[i]
                val n = lm[i]
                e[0] += SMOOTH * (n.x - e[0])
                e[1] += SMOOTH * (n.y - e[1])
                e[2] += SMOOTH * (n.z - e[2])
                e[3] += SMOOTH * (n.visibility - e[3])
            }
        }
        return smoothed!!.map { Landmark(it[0], it[1], it[2], it[3]) }
    }

    @Synchronized
    fun onFrame(input: FrameInput) {
        if (phase != Phase.POSITIONING && phase != Phase.HOLDING && phase != Phase.CONFIRMED) return
        val now = clock()

        if (phase == Phase.CONFIRMED) {
            if (now < confirmUntil) return
            phase = Phase.POSITIONING
            lastTick = 0
            report(step.detail, 0f)
            return
        }

        val dt = if (lastTick == 0L) 0L else minOf(now - lastTick, MAX_DT_MS)
        lastTick = now

        if (now - stepStart > STEP_TIMEOUT_MS) {
            phase = Phase.FAILED
            val common = issueCounts.maxByOrNull { it.value }?.key
            listener.onFailed(
                "Could not get a good ${step.id} view. " +
                    (common ?: "Check the lighting and that your whole body is in frame.")
            )
            return
        }

        val issue = judge(input)
        if (issue.inPosition != null) {
            val c = issue.inPosition
            badMs = 0
            holdMs += dt
            phase = Phase.HOLDING
            offer(c)
            report("Hold still", holdMs.toFloat() / HOLD_MS)
            if (holdMs >= HOLD_MS) finishStep()
        } else {
            badMs += dt
            issueCounts.merge(issue.message, 1, Int::plus)
            if (badMs >= BAD_RESET_MS) {
                holdMs = 0
                best.clear()
                phase = Phase.POSITIONING
            }
            report(issue.message, if (phase == Phase.HOLDING) holdMs.toFloat() / HOLD_MS else 0f)
        }
    }

    private class Judgement(val message: String, val inPosition: Candidate?)

    private fun judge(input: FrameInput): Judgement {
        if (input.poseCount > 1) {
            return Judgement("Only one person in frame - move away from mirrors.", null)
        }
        input.deviceIssue?.let { return Judgement(it, null) }

        val raw = input.landmarks
        if (raw == null || input.confidence == null || input.poseCount == 0) {
            noPose++
            if (noPose > NO_POSE_GRACE) smoothed = null
            return Judgement("Step into frame.", null)
        }
        noPose = 0

        val lm = smooth(raw)
        val a = ViewAssessment.frame(lm, input.width, input.height, step.facing)
        if (!a.usable) return Judgement(a.issues.first(), null)
        if (!matches(a)) return Judgement(wrongMessage(), null)

        val binary = MaskOps.threshold(input.confidence)
        val check = ViewAssessment.maskCheck(binary, input.width, input.height, lm)
        if (!check.usable) return Judgement(check.issues.first(), null)

        return Judgement(
            "",
            Candidate(
                score(a), a.spanRatio, input.width, input.height, binary, lm,
                input.photo,
            ),
        )
    }

    /** Keeps the best [KEEP_PER_VIEW] candidates, best first. */
    private fun offer(c: Candidate) {
        if (best.size >= KEEP_PER_VIEW && c.score <= best.last().score) return
        best.add(c)
        best.sortByDescending { it.score }
        while (best.size > KEEP_PER_VIEW) best.removeAt(best.size - 1)
    }

    /**
     * Cleans the kept silhouettes and re-checks them. Cleaning (opening and
     * keeping the biggest blob) is too slow to run on every frame, so it runs
     * once here, on the few that were kept.
     */
    private fun finishStep() {
        val cleaned = ArrayList<Frame>()
        var spanSum = 0f
        for (c in best) {
            val mask = MaskOps.largestComponent(
                MaskOps.open3(c.raw, c.width, c.height), c.width, c.height,
            )
            if (!ViewAssessment.maskCheck(mask, c.width, c.height, c.landmarks).usable) continue
            // Only the best kept frame of a view gets a photo: one per view
            // is all the comparison needs. [best] is sorted best first.
            val photo = if (cleaned.isEmpty()) {
                try { c.photo?.invoke() } catch (e: Exception) { null }
            } else null
            cleaned.add(Frame(c.width, c.height, mask, photo))
            spanSum += c.spanRatio
        }

        if (cleaned.isEmpty()) {
            // The outline looked fine raw but not once cleaned: start the hold over.
            holdMs = 0
            best.clear()
            phase = Phase.POSITIONING
            report("Your outline is not clear. Try a plainer background.", 0f)
            return
        }

        when (step) {
            Step.FRONT -> {
                frontSpan = spanSum / cleaned.size
                front.addAll(cleaned)
                phase = Phase.CONFIRMED
                confirmUntil = clock() + CONFIRM_MS
                report("Front captured.", 1f)
                step = Step.SIDE
                resetStep()
            }
            Step.SIDE -> {
                phase = Phase.DONE
                report("Side captured.", 1f)
                listener.onComplete(front.toList(), cleaned)
            }
        }
    }
}
