package com.example.transpose_mobile

import kotlin.math.max
import kotlin.math.sqrt

/** Pure streaming 10 ms microphone features. It retains no PCM samples. */
class RhythmFeatureExtractor {
    data class Feature(
        val frameStart: Long,
        val rms: Double,
        val novelty: Double,
        val onset: Boolean,
    )

    private val mutableFeatures = ArrayList<Feature>()
    val features: List<Feature> get() = mutableFeatures
    var framesSeen: Long = 0
        private set
    var peakRms = 0.0
        private set
    var clippedSamples: Long = 0
        private set
    var onsetCount = 0
        private set
    var ambientRms = 0.0
        private set
    private var windowSquares = 0.0
    private var windowFrames = 0
    private var previousRms = 0.0
    private var previousOnsetWindow = -100

    fun accept(pcm: ShortArray, length: Int) {
        require(length in 0..pcm.size)
        for (i in 0 until length) {
            val sample = pcm[i].toDouble() / 32768.0
            windowSquares += sample * sample
            if (sample >= 0.998 || sample <= -0.998) clippedSamples++
            windowFrames++
            framesSeen++
            if (windowFrames == WINDOW_FRAMES) completeWindow()
        }
    }

    private fun completeWindow() {
        check(mutableFeatures.size < MAX_WINDOWS) { "Feature capture exceeds ten minutes." }
        val index = mutableFeatures.size
        val rms = sqrt(windowSquares / WINDOW_FRAMES)
        val novelty = max(0.0, rms - previousRms)
        // The onset bit is deliberately conservative; RMS/novelty remain
        // available for future user review rather than claiming a beat map.
        val onset = index >= 20 &&
            index - previousOnsetWindow >= 8 &&
            rms >= max(0.025, ambientRms * 1.8) &&
            novelty >= max(0.018, ambientRms * 0.65)
        if (onset) {
            onsetCount++
            previousOnsetWindow = index
        }
        mutableFeatures.add(Feature(index.toLong() * WINDOW_FRAMES, rms, novelty, onset))
        peakRms = max(peakRms, rms)
        ambientRms = ambientRms * 0.98 + rms * 0.02
        previousRms = rms
        windowSquares = 0.0
        windowFrames = 0
    }

    /** Drop any incomplete 10 ms tail; it cannot represent a full feature. */
    fun finish() {
        windowSquares = 0.0
        windowFrames = 0
    }

    fun page(offset: Int, limit: Int): List<Feature> {
        require(offset >= 0 && limit in 1..1000)
        if (offset >= mutableFeatures.size) return emptyList()
        return mutableFeatures.subList(offset, minOf(offset + limit, mutableFeatures.size)).toList()
    }

    fun clear() {
        mutableFeatures.clear()
        framesSeen = 0
        peakRms = 0.0
        clippedSamples = 0
        onsetCount = 0
        ambientRms = 0.0
        windowSquares = 0.0
        windowFrames = 0
        previousRms = 0.0
        previousOnsetWindow = -100
    }

    companion object {
        const val RATE = 48_000
        const val WINDOW_FRAMES = 480
        const val MAX_WINDOWS = 60_000
    }
}
