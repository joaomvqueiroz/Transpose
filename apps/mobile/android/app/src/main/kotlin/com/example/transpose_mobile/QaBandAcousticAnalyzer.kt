package com.example.transpose_mobile

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/** Pure PCM analysis for the QA acoustic probe; no Android or transport clocks. */
internal object QaBandAcousticAnalyzer {
    const val RATE = 48_000
    private const val HOP = 48 // 1 ms
    private const val WINDOW = 240 // 5 ms
    private val tones = intArrayOf(1000, 1500, 2500, 3500)
    private val taper = DoubleArray(WINDOW) { n -> 0.5 - 0.5 * cos(2.0 * PI * n / (WINDOW - 1)) }
    private val taperSum = taper.sum()
    private val real = Array(tones.size) { tone ->
        DoubleArray(WINDOW) { n -> taper[n] * cos(2.0 * PI * tones[tone] * n / RATE) }
    }
    private val imaginary = Array(tones.size) { tone ->
        DoubleArray(WINDOW) { n -> taper[n] * sin(2.0 * PI * tones[tone] * n / RATE) }
    }

    data class Metrics(
        val conclusive: Boolean,
        val reason: String?,
        val pairs: Int,
        val eventsA: Int,
        val eventsB: Int,
        val unpairedA: Int,
        val unpairedB: Int,
        val medianDeltaMs: Double?,
        val p95AbsDeltaMs: Double?,
        val maxAbsDeltaMs: Double?,
        val jitterMadMs: Double?,
        val snrDbA: Double,
        val snrDbB: Double,
        val clippedFraction: Double,
    ) {
        fun asMap(): Map<String, Any?> = mapOf(
            "conclusive" to conclusive,
            "reason" to reason,
            "pairs" to pairs,
            "eventsA" to eventsA,
            "eventsB" to eventsB,
            "unpairedA" to unpairedA,
            "unpairedB" to unpairedB,
            "medianDeltaMs" to medianDeltaMs,
            "p95AbsDeltaMs" to p95AbsDeltaMs,
            "maxAbsDeltaMs" to maxAbsDeltaMs,
            "jitterMadMs" to jitterMadMs,
            "snrDbA" to snrDbA,
            "snrDbB" to snrDbB,
            "clippedFraction" to clippedFraction,
        )
    }

    fun analyze(samples: ShortArray, beatIntervalMs: Int): Metrics {
        require(beatIntervalMs in 250..1500)
        require(samples.size >= RATE * 2)
        val clipped = samples.count { abs(it.toInt()) >= 32760 }.toDouble() / samples.size
        val frames = (samples.size - WINDOW) / HOP + 1
        val a = DoubleArray(frames)
        val b = DoubleArray(frames)
        for (frame in 0 until frames) {
            val start = frame * HOP
            val amplitude = DoubleArray(4)
            for (tone in 0 until 4) {
                var re = 0.0
                var im = 0.0
                for (i in 0 until WINDOW) {
                    val value = samples[start + i] / 32768.0
                    re += value * real[tone][i]
                    im += value * imaginary[tone][i]
                }
                amplitude[tone] = 2.0 * sqrt(re * re + im * im) / taperSum
            }
            a[frame] = max(amplitude[0], amplitude[1])
            b[frame] = max(amplitude[2], amplitude[3])
        }
        val noiseA = max(1e-6, percentile(a, 0.5))
        val noiseB = max(1e-6, percentile(b, 0.5))
        val peakA = a.maxOrNull() ?: 0.0
        val peakB = b.maxOrNull() ?: 0.0
        val snrA = 20.0 * log10(max(peakA, 1e-6) / noiseA)
        val snrB = 20.0 * log10(max(peakB, 1e-6) / noiseB)
        val eventsA = detect(a, noiseA, beatIntervalMs)
        val eventsB = detect(b, noiseB, beatIntervalMs)
        val usedB = BooleanArray(eventsB.size)
        val deltas = ArrayList<Double>()
        val tolerance = min(100, beatIntervalMs / 3)
        for (eventA in eventsA) {
            var nearest = -1
            var distance = Int.MAX_VALUE
            for (index in eventsB.indices) {
                val diff = abs(eventsB[index] - eventA)
                if (!usedB[index] && diff < distance && diff <= tolerance) {
                    nearest = index
                    distance = diff
                }
            }
            if (nearest >= 0) {
                usedB[nearest] = true
                deltas += (eventsB[nearest] - eventA).toDouble() // HOP = 1 ms
            }
        }
        val missingA = eventsB.size - deltas.size
        val missingB = eventsA.size - deltas.size
        val minimumPairs = max(4, min(8, samples.size * 1000 / RATE / beatIntervalMs - 2))
        val reason = when {
            clipped > 0.001 -> "O microfone saturou."
            peakA < 0.005 || peakB < 0.005 -> "Uma das bandas é demasiado fraca para medir."
            snrA < 12.0 || snrB < 12.0 -> "Um dos dois cliques não se destaca do ruído."
            deltas.size < minimumPairs -> "Poucos pares de cliques detetados."
            missingA != 0 || missingB != 0 -> "Há cliques sem par; a medição é inconclusiva."
            irregular(eventsA, beatIntervalMs) || irregular(eventsB, beatIntervalMs) ->
                "A sequência contém falhas ou ataques ambíguos."
            else -> null
        }
        val signedMedian = if (deltas.isEmpty()) null else percentile(deltas.toDoubleArray(), 0.5)
        val absolute = deltas.map { abs(it) }.toDoubleArray()
        return Metrics(
            conclusive = reason == null,
            reason = reason,
            pairs = deltas.size,
            eventsA = eventsA.size,
            eventsB = eventsB.size,
            unpairedA = missingA,
            unpairedB = missingB,
            medianDeltaMs = signedMedian,
            p95AbsDeltaMs = if (absolute.isEmpty()) null else percentile(absolute, 0.95),
            maxAbsDeltaMs = absolute.maxOrNull(),
            jitterMadMs = if (signedMedian == null) null else
                percentile(deltas.map { abs(it - signedMedian) }.toDoubleArray(), 0.5),
            snrDbA = snrA,
            snrDbB = snrB,
            clippedFraction = clipped,
        )
    }

    private fun detect(envelope: DoubleArray, noise: Double, intervalMs: Int): List<Int> {
        val globalPeak = envelope.maxOrNull() ?: 0.0
        val threshold = max(noise * 5.0, globalPeak * 0.14)
        val candidates = ArrayList<Pair<Int, Double>>()
        var at = 0
        while (at < envelope.size) {
            if (envelope[at] < threshold) { at++; continue }
            val begin = at
            var peak = at
            while (at < envelope.size && envelope[at] >= threshold) {
                if (envelope[at] > envelope[peak]) peak = at
                at++
            }
            if (at - begin < 3) continue
            var onset = peak
            val onsetThreshold = max(noise * 3.0, envelope[peak] * 0.08)
            while (onset > 0 && envelope[onset - 1] >= onsetThreshold) onset--
            candidates += onset to envelope[peak]
        }
        val events = ArrayList<Pair<Int, Double>>()
        val refractory = (intervalMs * 0.55).roundToInt()
        for (candidate in candidates) {
            if (events.isNotEmpty() && candidate.first - events.last().first < refractory) {
                if (candidate.second > events.last().second) events[events.lastIndex] = candidate
            } else events += candidate
        }
        return events.map { it.first }
    }

    private fun irregular(events: List<Int>, intervalMs: Int): Boolean {
        if (events.size < 2) return true
        return events.zipWithNext().any { (left, right) ->
            abs((right - left) - intervalMs) > max(20.0, intervalMs * 0.15)
        }
    }

    private fun percentile(values: DoubleArray, fraction: Double): Double {
        if (values.isEmpty()) return 0.0
        val sorted = values.sorted()
        return sorted[(ceil(sorted.size * fraction).toInt() - 1).coerceIn(0, sorted.lastIndex)]
    }
}
