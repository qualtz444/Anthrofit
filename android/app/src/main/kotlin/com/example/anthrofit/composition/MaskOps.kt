package com.example.anthrofit.composition

/**
 * Silhouette post-processing for body composition.
 *
 * Ported from the bodycomp project's segment.py / mask.js (MIT). No Android
 * types in here, so all of it runs on a plain JVM and is unit-tested.
 *
 * A mask is a row-major ByteArray, one byte per pixel, 0 = background and
 * 1 = person.
 */
object MaskOps {

    /**
     * Person-confidence cut. Deliberately above 0.5: bodycomp measured that
     * over-segmentation cost up to +0.70 cm of waist error while the same
     * amount of under-segmentation cost nothing, so the cut leans toward
     * trimming the outline.
     */
    const val ALPHA_CUT = 0.62f

    /** Confidence (0..1 per pixel) to a 0/1 mask. */
    fun threshold(confidence: FloatArray, cut: Float = ALPHA_CUT): ByteArray {
        val out = ByteArray(confidence.size)
        for (i in confidence.indices) if (confidence[i] >= cut) out[i] = 1
        return out
    }

    /** 3x3 opening (erode, then dilate) to drop speckle. Border pixels clear. */
    fun open3(mask: ByteArray, w: Int, h: Int): ByteArray {
        val eroded = ByteArray(w * h)
        for (y in 1 until h - 1) {
            for (x in 1 until w - 1) {
                var all = true
                loop@ for (dy in -1..1) {
                    for (dx in -1..1) {
                        if (mask[(y + dy) * w + (x + dx)].toInt() == 0) {
                            all = false
                            break@loop
                        }
                    }
                }
                if (all) eroded[y * w + x] = 1
            }
        }
        val dilated = ByteArray(w * h)
        for (y in 1 until h - 1) {
            for (x in 1 until w - 1) {
                var any = false
                loop@ for (dy in -1..1) {
                    for (dx in -1..1) {
                        if (eroded[(y + dy) * w + (x + dx)].toInt() != 0) {
                            any = true
                            break@loop
                        }
                    }
                }
                if (any) dilated[y * w + x] = 1
            }
        }
        return dilated
    }

    /**
     * Keeps only the biggest 8-connected blob, which drops a mirror image,
     * furniture or a second person. The first of equal-sized blobs wins.
     */
    fun largestComponent(mask: ByteArray, w: Int, h: Int): ByteArray {
        val n = w * h
        val label = IntArray(n) { -1 }
        val stack = IntArray(n)
        var best = -1
        var bestSize = 0
        var current = 0

        for (i in 0 until n) {
            if (mask[i].toInt() == 0 || label[i] >= 0) continue
            var sp = 0
            var size = 0
            stack[sp++] = i
            label[i] = current
            while (sp > 0) {
                val p = stack[--sp]
                size++
                val px = p % w
                val py = p / w
                for (dy in -1..1) {
                    for (dx in -1..1) {
                        val nx = px + dx
                        val ny = py + dy
                        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue
                        val q = ny * w + nx
                        if (mask[q].toInt() != 0 && label[q] < 0) {
                            label[q] = current
                            stack[sp++] = q
                        }
                    }
                }
            }
            if (size > bestSize) {
                bestSize = size
                best = current
            }
            current++
        }

        val out = ByteArray(n)
        if (best < 0) return out
        for (i in 0 until n) if (label[i] == best) out[i] = 1
        return out
    }

    /** Confidence mask to a clean silhouette: threshold, open, keep the biggest blob. */
    fun build(confidence: FloatArray, w: Int, h: Int, cut: Float = ALPHA_CUT): ByteArray =
        largestComponent(open3(threshold(confidence, cut), w, h), w, h)

    class Bounds(
        val top: Int,
        val bottom: Int,
        val left: Int,
        val right: Int,
        val area: Int,
    ) {
        val isEmpty: Boolean get() = top < 0
    }

    fun bounds(mask: ByteArray, w: Int, h: Int): Bounds {
        var top = -1
        var bottom = -1
        var left = w
        var right = -1
        var area = 0
        for (y in 0 until h) {
            val off = y * w
            for (x in 0 until w) {
                if (mask[off + x].toInt() == 0) continue
                area++
                if (top < 0) top = y
                bottom = y
                if (x < left) left = x
                if (x > right) right = x
            }
        }
        return Bounds(top, bottom, left, right, area)
    }

    /**
     * Run-length encoding sent to Flutter, so a mask costs a few kilobytes
     * rather than a few hundred.
     *
     *   [width, height, then for each row: runCount, (start, length) × runCount]
     *
     * The Dart side decodes the same layout (lib/composition/mask_codec.dart).
     */
    fun encodeRuns(mask: ByteArray, w: Int, h: Int): IntArray {
        val out = ArrayList<Int>()
        out.add(w)
        out.add(h)
        for (y in 0 until h) {
            val off = y * w
            val runs = ArrayList<Int>()
            var x = 0
            while (x < w) {
                if (mask[off + x].toInt() == 0) {
                    x++
                    continue
                }
                val start = x
                while (x < w && mask[off + x].toInt() != 0) x++
                runs.add(start)
                runs.add(x - start)
            }
            out.add(runs.size / 2)
            out.addAll(runs)
        }
        return out.toIntArray()
    }

    /** Inverse of [encodeRuns]. Returns null if the data is not a whole mask. */
    fun decodeRuns(data: IntArray): Triple<ByteArray, Int, Int>? {
        if (data.size < 2) return null
        val w = data[0]
        val h = data[1]
        if (w <= 0 || h <= 0) return null
        val mask = ByteArray(w * h)
        var i = 2
        for (y in 0 until h) {
            if (i >= data.size) return null
            val count = data[i++]
            for (r in 0 until count) {
                if (i + 1 >= data.size) return null
                val start = data[i++]
                val len = data[i++]
                if (start < 0 || len < 0 || start + len > w) return null
                for (x in start until start + len) mask[y * w + x] = 1
            }
        }
        return if (i == data.size) Triple(mask, w, h) else null
    }
}
