# youtube_native_audio

iOS-only plugin. On iPhone, WebKit does not route YouTube's native HLS audio
into Web Audio, so the in-page pitch/EQ bridge cannot process it. This plugin
fetches the video's audio-only m4a stream with
[YouTubeKit](https://github.com/alexeichhorn/YouTubeKit) (local extraction
only), caches it, and plays it through `AVAudioEngine` with
`AVAudioUnitTimePitch`, `AVAudioUnitEQ`, `AVAudioUnitDelay` and
`AVAudioUnitReverb`. The web player is muted and the native clock follows it.

Fetching YouTube media directly is against YouTube's Terms of Service; this is
for personal, sideloaded builds only and must not ship to the App Store.
