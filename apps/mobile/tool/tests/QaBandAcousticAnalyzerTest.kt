package com.example.transpose_mobile

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.roundToInt
import kotlin.math.sin

/** Standalone pure-Kotlin unit runner; no Android runtime or microphone needed. */
object QaBandAcousticAnalyzerTest {
    @JvmStatic fun main(args: Array<String>) {
        val positive = fixture(deltaMs = 13, gainA = 0.5, gainB = 0.16, noise = 0.004)
        val plus = QaBandAcousticAnalyzer.analyze(positive, 500)
        check(plus.conclusive) { "positive offset rejected: $plus" }
        check(plus.pairs >= 12) { "too few positive pairs: $plus" }
        check(abs(plus.medianDeltaMs!! - 13.0) <= 3.0) { "positive offset bias: $plus" }

        val negative = fixture(deltaMs = -9, gainA = 0.13, gainB = 0.55, noise = 0.007)
        val minus = QaBandAcousticAnalyzer.analyze(negative, 500)
        check(minus.conclusive) { "negative offset rejected: $minus" }
        check(abs(minus.medianDeltaMs!! + 9.0) <= 3.0) { "negative offset bias: $minus" }

        val absent = QaBandAcousticAnalyzer.analyze(fixture(deltaMs = 0, omitAllB = true), 500)
        check(!absent.conclusive) { "absent B should be inconclusive: $absent" }

        val dropped = QaBandAcousticAnalyzer.analyze(fixture(deltaMs = 7, omitBBeat = 8), 500)
        check(!dropped.conclusive) { "missing B click should be inconclusive: $dropped" }

        val noisy = QaBandAcousticAnalyzer.analyze(fixture(deltaMs = 0, gainA = 0.0, gainB = 0.0, noise = 0.04), 500)
        check(!noisy.conclusive) { "noise-only recording should be inconclusive: $noisy" }

        val clipped = fixture(deltaMs = 0)
        for (i in 0 until 10_000) clipped[i] = Short.MAX_VALUE
        val saturation = QaBandAcousticAnalyzer.analyze(clipped, 500)
        check(!saturation.conclusive && saturation.reason!!.contains("saturou")) {
            "clipping should be rejected: $saturation"
        }
        println("positive: pairs=${plus.pairs}, median=${plus.medianDeltaMs} ms, p95Abs=${plus.p95AbsDeltaMs} ms, SNR A/B=${plus.snrDbA}/${plus.snrDbB} dB")
        println("negative: pairs=${minus.pairs}, median=${minus.medianDeltaMs} ms, p95Abs=${minus.p95AbsDeltaMs} ms, SNR A/B=${minus.snrDbA}/${minus.snrDbB} dB")
        println("QaBandAcousticAnalyzer: six synthetic cases passed; calibration on real hardware still required")
    }

    private fun fixture(
        deltaMs: Int,
        gainA: Double = 0.42,
        gainB: Double = 0.30,
        noise: Double = 0.002,
        omitAllB: Boolean = false,
        omitBBeat: Int = -1,
    ): ShortArray {
        val rate = QaBandAcousticAnalyzer.RATE
        val pcm = DoubleArray(rate * 12)
        var random = 0x12345678
        for (i in pcm.indices) {
            random = random * 1_664_525 + 1_013_904_223
            pcm[i] = ((random ushr 8) / 16_777_215.0 * 2.0 - 1.0) * noise
        }
        for (beat in 0 until 18) {
            val startA = rate + beat * rate / 2
            addClick(pcm, startA, if (beat % 4 == 0) 1500 else 1000, gainA)
            if (!omitAllB && beat != omitBBeat) {
                addClick(pcm, startA + deltaMs * rate / 1000,
                    if (beat % 4 == 0) 3500 else 2500, gainB)
            }
        }
        return ShortArray(pcm.size) { i ->
            (pcm[i].coerceIn(-1.0, 1.0) * 32767.0).roundToInt().toShort()
        }
    }

    private fun addClick(pcm: DoubleArray, start: Int, frequency: Int, gain: Double) {
        val frames = 1200
        for (i in 0 until frames) {
            val phase = i / 1199.0
            val value = sin(2 * PI * frequency * i / QaBandAcousticAnalyzer.RATE) *
                sin(PI * phase) * exp(-5 * phase) * gain
            if (start + i in pcm.indices) pcm[start + i] += value
        }
    }
}
