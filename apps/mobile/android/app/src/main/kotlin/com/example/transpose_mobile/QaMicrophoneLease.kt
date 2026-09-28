package com.example.transpose_mobile

import java.util.concurrent.atomic.AtomicBoolean

/** Prevent QA-only microphone probes from recording at the same time. */
internal object QaMicrophoneLease {
    val active = AtomicBoolean(false)
}
