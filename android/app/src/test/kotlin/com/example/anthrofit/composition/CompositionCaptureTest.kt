package com.example.anthrofit.composition

import org.junit.Assert.assertEquals
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mask post-processing, frame checks and the front/side capture flow. */
class CompositionCaptureTest {

    // ---- helpers ------------------------------------------------------------

    private fun mask(w: Int, h: Int, vararg rows: String): ByteArray {
        val out = ByteArray(w * h)
        rows.forEachIndexed { y, row ->
            row.forEachIndexed { x, c -> if (c == '#') out[y * w + x] = 1 }
        }
        return out
    }

    private fun lms(block: (Int) -> Landmark): List<Landmark> = List(33, block)

    // A 120 x 160 frame with a person drawn in it. Front is wide, side is narrow.
    private val W = 120
    private val H = 160

    private fun pose(front: Boolean, visibility: Float = 0.95f): List<Landmark> {
        val half = if (front) 0.12f else 0.02f
        val wristOff = if (front) 0.20f else 0.03f
        return lms { i ->
            when (i) {
                ViewAssessment.NOSE -> Landmark(0.5f, 0.09f, 0f, visibility)
                ViewAssessment.L_SHOULDER -> Landmark(0.5f - half, 0.25f, 0f, visibility)
                ViewAssessment.R_SHOULDER -> Landmark(0.5f + half, 0.25f, 0f, visibility)
                ViewAssessment.L_HIP -> Landmark(0.5f - half / 2, 0.55f, 0f, visibility)
                ViewAssessment.R_HIP -> Landmark(0.5f + half / 2, 0.55f, 0f, visibility)
                ViewAssessment.L_WRIST -> Landmark(0.5f - wristOff, 0.5f, 0f, visibility)
                ViewAssessment.R_WRIST -> Landmark(0.5f + wristOff, 0.5f, 0f, visibility)
                ViewAssessment.L_ANKLE -> Landmark(0.48f, 0.90f, 0f, visibility)
                ViewAssessment.R_ANKLE -> Landmark(0.52f, 0.90f, 0f, visibility)
                else -> Landmark(0.5f, 0.5f, 0f, visibility)
            }
        }
    }

    /** Person confidence: high inside the body, low outside. [bottom] cuts the legs short. */
    private fun confidence(front: Boolean, bottom: Int = 147): FloatArray {
        val out = FloatArray(W * H) { 0.05f }
        val half = if (front) 15 else 9
        for (y in 12..bottom) for (x in (W / 2 - half)..(W / 2 + half)) out[y * W + x] = 0.95f
        return out
    }

    private fun input(
        front: Boolean,
        poses: Int = 1,
        bottom: Int = 147,
        deviceIssue: String? = null,
        lm: List<Landmark>? = pose(front),
        photo: (() -> ByteArray)? = null,
    ) = SilhouetteCapture.FrameInput(
        landmarks = lm,
        poseCount = poses,
        confidence = confidence(front, bottom),
        width = W,
        height = H,
        deviceIssue = deviceIssue,
        photo = photo,
    )

    private class Recorder : SilhouetteCapture.Listener {
        val progress = ArrayList<SilhouetteCapture.Progress>()
        var front: List<SilhouetteCapture.Frame>? = null
        var side: List<SilhouetteCapture.Frame>? = null
        var failure: String? = null
        override fun onProgress(progress: SilhouetteCapture.Progress) { this.progress.add(progress) }
        override fun onComplete(front: List<SilhouetteCapture.Frame>, side: List<SilhouetteCapture.Frame>) {
            this.front = front
            this.side = side
        }
        override fun onFailed(reason: String) { failure = reason }
        val last get() = progress.last()
    }

    private class Clock { var now = 1_000L; fun tick(ms: Long) { now += ms } }

    private fun capture(): Triple<SilhouetteCapture, Recorder, Clock> {
        val clock = Clock()
        val rec = Recorder()
        val cap = SilhouetteCapture({ clock.now }, rec)
        cap.start()
        return Triple(cap, rec, clock)
    }

    private fun feed(cap: SilhouetteCapture, clock: Clock, n: Int, ms: Long = 100, make: () -> SilhouetteCapture.FrameInput) {
        repeat(n) { clock.tick(ms); cap.onFrame(make()) }
    }

    // ---- masks --------------------------------------------------------------

    @Test fun thresholdSitsAtTheConservativeCut() {
        val out = MaskOps.threshold(floatArrayOf(0.61f, 0.62f, 0.9f, 0f))
        assertEquals(listOf<Byte>(0, 1, 1, 0), out.toList())
    }

    @Test fun openingDropsSpeckleButKeepsABody() {
        val w = 12; val h = 12
        val m = ByteArray(w * h)
        for (y in 3..8) for (x in 3..8) m[y * w + x] = 1   // solid 6x6 block
        m[1 * w + 10] = 1                                   // lone speckle
        val out = MaskOps.open3(m, w, h)
        assertEquals(0, out[1 * w + 10].toInt())
        assertEquals(1, out[5 * w + 5].toInt())
        assertEquals(1, out[3 * w + 3].toInt())             // corners survive the open
    }

    @Test fun largestComponentDropsTheSmallerBlob() {
        val w = 10; val h = 6
        val m = mask(w, h,
            "##....#...",
            "##....#...",
            "##........",
            "##........",
            "..........",
            "..........")
        val out = MaskOps.largestComponent(m, w, h)
        assertEquals(8, out.count { it.toInt() == 1 })
        assertEquals(0, out[0 * w + 6].toInt())
    }

    @Test fun diagonalPixelsAreOneBlob() {
        val w = 4; val h = 4
        val m = mask(w, h, "#...", ".#..", "..#.", "...#")
        assertEquals(4, MaskOps.largestComponent(m, w, h).count { it.toInt() == 1 })
    }

    @Test fun boundsOfAnEmptyMaskAreEmpty() {
        assertTrue(MaskOps.bounds(ByteArray(20), 5, 4).isEmpty)
        val b = MaskOps.bounds(mask(5, 4, ".....", ".##..", ".##..", "....."), 5, 4)
        assertEquals(1, b.top); assertEquals(2, b.bottom)
        assertEquals(1, b.left); assertEquals(2, b.right)
        assertEquals(4, b.area)
    }

    @Test fun runLengthEncodingHasTheDocumentedLayout() {
        val enc = MaskOps.encodeRuns(mask(5, 2, "##.#.", "....."), 5, 2)
        // [w, h, row0: 2 runs (0,2) (3,1), row1: 0 runs]
        assertEquals(listOf(5, 2, 2, 0, 2, 3, 1, 0), enc.toList())
    }

    @Test fun runLengthEncodingRoundTrips() {
        val w = 40; val h = 30
        val m = ByteArray(w * h)
        for (y in 4 until 26) for (x in 10 until 30) if ((x + y) % 7 != 0) m[y * w + x] = 1
        val (decoded, dw, dh) = MaskOps.decodeRuns(MaskOps.encodeRuns(m, w, h))!!
        assertEquals(w, dw); assertEquals(h, dh)
        assertEquals(m.toList(), decoded.toList())
    }

    @Test fun truncatedOrPaddedRunDataIsRejected() {
        val enc = MaskOps.encodeRuns(mask(5, 2, "##.#.", "....."), 5, 2)
        assertNull(MaskOps.decodeRuns(enc.copyOf(enc.size - 1)))
        assertNull(MaskOps.decodeRuns(enc + 0))
        assertNull(MaskOps.decodeRuns(intArrayOf(5)))
    }

    // ---- frame assessment ---------------------------------------------------

    @Test fun aSquareOnPoseWithArmsOutIsUsable() {
        val a = ViewAssessment.frame(pose(front = true), W, H, assumeFacing = true)
        assertTrue(a.issues.toString(), a.usable)
        assertTrue(a.spanRatio > SilhouetteCapture.FRONT_SPAN_MIN)
    }

    @Test fun armsAgainstTheBodyAreRefusedFacingTheCamera() {
        val tight = pose(front = true).toMutableList()
        tight[ViewAssessment.L_WRIST] = Landmark(0.43f, 0.5f, 0f, 0.95f)
        tight[ViewAssessment.R_WRIST] = Landmark(0.57f, 0.5f, 0f, 0.95f)
        val a = ViewAssessment.frame(tight, W, H, assumeFacing = true)
        assertFalse(a.usable)
        assertTrue(a.issues.any { it.contains("arms out") })
    }

    @Test fun inProfileTheArmCheckDoesNotApply() {
        val a = ViewAssessment.frame(pose(front = false), W, H, assumeFacing = false)
        assertTrue(a.issues.toString(), a.usable)
        assertTrue(a.spanRatio < SilhouetteCapture.FRONT_SPAN_MIN)
    }

    @Test fun missingOrShortLandmarkListsAreUnusable() {
        assertFalse(ViewAssessment.frame(null, W, H).usable)
        assertFalse(ViewAssessment.frame(pose(true).take(20), W, H).usable)
    }

    @Test fun feetOutOfFrameAreRefused() {
        val lm = pose(true).toMutableList()
        lm[ViewAssessment.L_ANKLE] = Landmark(0.48f, 1.2f, 0f, 0.05f)
        lm[ViewAssessment.R_ANKLE] = Landmark(0.52f, 1.2f, 0f, 0.05f)
        assertTrue(ViewAssessment.frame(lm, W, H, true).issues.any { it.contains("feet") })
    }

    @Test fun anOutlineThatLostTheLegsIsRefused() {
        val cut = MaskOps.threshold(confidence(true, bottom = 100))
        val check = ViewAssessment.maskCheck(cut, W, H, pose(true))
        assertFalse(check.usable)
        assertTrue(check.issues.any { it.contains("legs") })

        val whole = MaskOps.threshold(confidence(true))
        assertTrue(ViewAssessment.maskCheck(whole, W, H, pose(true)).usable)
    }

    @Test fun aBodyCutOffAtTheEdgeIsRefused() {
        val c = FloatArray(W * H) { 0.05f }
        for (y in 0 until H) for (x in 40..80) c[y * W + x] = 0.95f
        val check = ViewAssessment.maskCheck(MaskOps.threshold(c), W, H, pose(true))
        assertFalse(check.usable)
        assertTrue(check.issues.any { it.contains("cut off") })
    }

    // ---- the capture flow ---------------------------------------------------

    @Test fun frontThenSideCompletesWithTheBestFramesOfEach() {
        val (cap, rec, clock) = capture()
        feed(cap, clock, 20) { input(front = true) }
        assertEquals(SilhouetteCapture.Phase.CONFIRMED, rec.last.phase)
        assertEquals("Front captured.", rec.last.message)

        // The confirmation holds, then the side step opens.
        clock.tick(SilhouetteCapture.CONFIRM_MS + 10)
        cap.onFrame(input(front = false))
        assertEquals(SilhouetteCapture.Step.SIDE, rec.last.step)

        feed(cap, clock, 20) { input(front = false) }
        assertEquals(SilhouetteCapture.Phase.DONE, cap.phase)

        assertEquals(SilhouetteCapture.KEEP_PER_VIEW, rec.front!!.size)
        assertEquals(SilhouetteCapture.KEEP_PER_VIEW, rec.side!!.size)
        // The front outline is wider than the side one.
        assertTrue(MaskOps.bounds(rec.front!![0].mask, W, H).area >
                MaskOps.bounds(rec.side!![0].mask, W, H).area)
        assertNull(rec.failure)
    }

    @Test fun selectedFramesKeepTheirOriginalPhotos() {
        val (cap, rec, clock) = capture()
        val frontPhoto = byteArrayOf(1, 2, 3)
        val sidePhoto = byteArrayOf(4, 5, 6)

        feed(cap, clock, 20) { input(front = true, photo = { frontPhoto }) }
        clock.tick(SilhouetteCapture.CONFIRM_MS + 10)
        cap.onFrame(input(front = false, photo = { sidePhoto }))
        feed(cap, clock, 20) { input(front = false, photo = { sidePhoto }) }

        assertArrayEquals(frontPhoto, rec.front!![0].photo)
        assertArrayEquals(sidePhoto, rec.side!![0].photo)
    }

    @Test fun facingAwayFromTheAskedPositionNeverAdvances() {
        val (cap, rec, clock) = capture()
        feed(cap, clock, 40) { input(front = false) }   // side pose, front asked
        assertEquals(SilhouetteCapture.Step.FRONT, cap.step)
        assertNotNull(rec.progress.find { it.message.contains("face the camera") })
        assertTrue(rec.last.holdProgress == 0f)
    }

    @Test fun theSideStepRefusesAFrontPose() {
        val (cap, rec, clock) = capture()
        feed(cap, clock, 20) { input(front = true) }
        clock.tick(SilhouetteCapture.CONFIRM_MS + 10)
        cap.onFrame(input(front = true))
        feed(cap, clock, 30) { input(front = true) }
        assertEquals(SilhouetteCapture.Step.SIDE, cap.step)
        assertTrue(rec.last.message.contains("turning"))
        assertNull(rec.side)
    }

    @Test fun aSecondPersonStopsTheHold() {
        val (cap, rec, clock) = capture()
        feed(cap, clock, 30) { input(front = true, poses = 2) }
        assertTrue(rec.last.message.contains("one person"))
        assertEquals(SilhouetteCapture.Phase.POSITIONING, cap.phase)
    }

    @Test fun aTiltedPhoneStopsTheHold() {
        val (cap, rec, clock) = capture()
        feed(cap, clock, 30) { input(front = true, deviceIssue = "Stand the phone up straight.") }
        assertEquals("Stand the phone up straight.", rec.last.message)
        assertEquals(SilhouetteCapture.Phase.POSITIONING, cap.phase)
    }

    @Test fun lostLegsInTheOutlineNeverCapture() {
        val (cap, rec, clock) = capture()
        feed(cap, clock, 40) { input(front = true, bottom = 100) }
        assertEquals(SilhouetteCapture.Step.FRONT, cap.step)
        assertTrue(rec.last.message.contains("legs"))
    }

    @Test fun movingOutOfPositionRestartsTheHold() {
        val (cap, rec, clock) = capture()
        feed(cap, clock, 6) { input(front = true) }             // 0.6 s of 1.2 s
        assertEquals(SilhouetteCapture.Phase.HOLDING, cap.phase)
        feed(cap, clock, 12) { input(front = true, poses = 0, lm = null) }  // walk away
        assertEquals(SilhouetteCapture.Phase.POSITIONING, cap.phase)
        // Back in place, it must hold the full time again.
        feed(cap, clock, 6) { input(front = true) }
        assertEquals(SilhouetteCapture.Phase.HOLDING, cap.phase)
        assertNull(rec.front)
    }

    @Test fun aLongGapIsNotCountedAsTimeInPosition() {
        val (cap, _, clock) = capture()
        cap.onFrame(input(front = true))
        clock.tick(30_000)                      // app was backgrounded
        cap.onFrame(input(front = true))
        assertTrue(cap.phase != SilhouetteCapture.Phase.CONFIRMED)
    }

    @Test fun gettingStuckEndsInAFailureThatSaysWhy() {
        val (cap, rec, clock) = capture()
        repeat(700) { clock.tick(100); cap.onFrame(input(front = true, bottom = 100)) }
        assertEquals(SilhouetteCapture.Phase.FAILED, cap.phase)
        assertTrue(rec.failure!!.contains("front"))
        assertTrue(rec.failure!!.contains("legs"))
    }

    @Test fun cancelStopsEverything() {
        val (cap, rec, clock) = capture()
        feed(cap, clock, 3) { input(front = true) }
        cap.cancel()
        val n = rec.progress.size
        feed(cap, clock, 30) { input(front = true) }
        assertEquals(n, rec.progress.size)
    }
}
