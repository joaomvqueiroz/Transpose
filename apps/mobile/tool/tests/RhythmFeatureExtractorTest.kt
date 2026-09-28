package com.example.transpose_mobile

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.roundToInt
import kotlin.math.sin

/** Pure Kotlin runner: generated pulses/noise only, no Android or microphone. */
object RhythmFeatureExtractorTest {
    @JvmStatic fun main(args: Array<String>) {
        val beats120 = (0 until 8).map { 500 + it * 500 }
        val beats90 = (0 until 8).map { 6000 + (it * 60000.0 / 90).roundToInt() }
        val expected = beats120 + beats90
        val extractor = RhythmFeatureExtractor()
        val pulse = fixture(11_500, expected, noise = 0.004)
        feedInUnevenChunks(extractor, pulse)
        extractor.finish()
        val detected = extractor.features.filter { it.onset }.map { it.frameStart / 48.0 }
        check(extractor.features.size == 1150) { "Expected 100 Hz features" }
        check(detected.size == expected.size) { "Lost or spurious onsets: $detected" }
        for (beat in expected) {
            check(detected.any { abs(it - beat) <= 20 }) { "Missing beat $beat ms: $detected" }
        }
        check(detected.none { it in 4500.0..5900.0 }) { "Pause generated an onset" }
        val firstIntervals = detected.filter { it in 500.0..4100.0 }.zipWithNext { a, b -> b - a }
        val secondIntervals = detected.filter { it in 6000.0..11000.0 }.zipWithNext { a, b -> b - a }
        check(firstIntervals.all { abs(it - 500.0) <= 20 }) { "120 BPM intervals: $firstIntervals" }
        check(secondIntervals.all { abs(it - 666.7) <= 20 }) { "90 BPM intervals: $secondIntervals" }
        check(extractor.peakRms > 0.05 && extractor.ambientRms >= 0.0)
        check(extractor.page(100, 50).size == 50 && extractor.page(99999, 50).isEmpty())

        val silent = RhythmFeatureExtractor()
        feedInUnevenChunks(silent, ShortArray(48_000 * 3))
        silent.finish()
        check(silent.onsetCount == 0 && silent.peakRms == 0.0)

        val noise = RhythmFeatureExtractor()
        feedInUnevenChunks(noise, fixture(5000, emptyList(), noise = 0.04))
        noise.finish()
        check(noise.onsetCount == 0) { "Noise generated ${noise.onsetCount} onsets" }

        val tail = RhythmFeatureExtractor()
        tail.accept(ShortArray(123) { Short.MAX_VALUE }, 123)
        tail.finish()
        check(tail.features.isEmpty()) { "Incomplete 10 ms tail should not become a feature" }
        tail.clear()
        check(tail.framesSeen == 0L && tail.features.isEmpty())

        println("RhythmFeatureExtractor: 120→90 BPM, pause, silence, noise and tail passed; " +
            "${extractor.features.size} feature windows, ${extractor.onsetCount} onsets")
    }

    private fun feedInUnevenChunks(extractor: RhythmFeatureExtractor, samples: ShortArray) {
        var offset = 0
        while (offset < samples.size) {
            val length = minOf(317, samples.size - offset)
            val chunk = samples.copyOfRange(offset, offset + length)
            extractor.accept(chunk, length)
            chunk.fill(0)
            offset += length
        }
    }

    private fun fixture(durationMs: Int, beatsMs: List<Int>, noise: Double): ShortArray {
        val samples = ShortArray(durationMs * 48)
        var random = 0x13579BDF
        for (i in samples.indices) {
            val ms = i / 48.0
            val elapsed = beatsMs.firstOrNull { ms >= it && ms < it + 25 }
            val click = if (elapsed == null) 0.0 else {
                val phase = (ms - elapsed) / 25.0
                sin(2 * PI * 1000 * i / 48_000.0) * exp(-5 * phase) * 0.8
            }
            random = random * 1664525 + 1013904223
            val hiss = ((random ushr 16) / 65535.0 * 2 - 1) * noise
            samples[i] = ((click + hiss).coerceIn(-1.0, 1.0) * 32767).roundToInt().toShort()
        }
        return samples
    }
}
