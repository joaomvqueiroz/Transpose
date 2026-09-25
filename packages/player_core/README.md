# Player Core

Pure Dart domain package for player lifecycle and media-source contracts.

The package deliberately has no Flutter, media SDK, persistence, platform, or
DSP dependency. Widgets observe the public state; they do not own playback
state.

## Event boundary

The public package facade exposes `PlayerStateView`, which is read-only. The
internal `PlayerStateMachine.applyConfirmedEvent` accepts facts confirmed by
the future player/engine adapter. A UI tap is an intent and cannot mutate the
public view. For example, internal `PlayerEvent.play` means playback start was
confirmed, not merely that the Play button was tapped. This keeps the UI out of
`PLAYING` while an engine remains paused or fails to start.

Transitions not defined by `STATE_MACHINES.md` throw
`InvalidPlayerTransition` without mutating state. Reentrant transitions from a
synchronous observer are also rejected before mutation.

`states` broadcasts future changes. A screen mounted later (including
fullscreen) reads `state` first, then subscribes to `states`; it does not
create another state machine.

## Media sources

`MediaSource` carries a stable ID, source type, display name, authorized
locator, optional duration hint, and typed capabilities. `LocalFileSource`
supports `file://` and Android `content://` locators. It describes media only;
the `MediaLoader` adapter opens and prepares it.

Diagnostics redact locators and user-facing metadata. Code that persists or
opens a source can explicitly access `sourceLocator`, but must not log it.
For Android `content://` URIs, the locator describes the selected item;
persistable permission grants and reopening after process death belong to the
platform adapter. The capability flags state what the source
permits, while effective playback support also depends on its format, decoder,
and selected platform adapter.

## Load and unload

`PlayerSession` owns one `LoadedMedia` at a time. Its serialized commands
release the old resource before loading a replacement, and `READY` is emitted
only after `MediaLoader.load` succeeds. A failed load emits `ERROR`; an unload
releases resources before emitting `IDLE`. The loader must clean partial
resources if its own `load` fails. ADR-012 now selects a native local-media
pipeline, but that adapter is not implemented; this package proves lifecycle behavior with a fake adapter, not
device playback.

## Play and pause

`LoadedMedia.play` and `pause` are confirmation boundaries. The session emits
`PLAYING` only after the adapter confirms output started, and `PAUSED` only
after it confirms output stopped. Failed commands move the session to `ERROR`
and trigger best-effort release of the output resource, with a sanitized
`PLAYER_PLAY_FAILED` or `PLAYER_PAUSE_FAILED` code. Repeated
Play/Pause requests do not issue duplicate backend calls. Device latency gates
still require a native adapter and physical measurement.

## Seek

`PlayerSession.seek` validates the source capability and target range before
contacting the adapter. Requests are serialized with load/play/pause, and an
acknowledged seek preserves the logical playback state. The session exposes
the adapter's current position; a failed seek returns a sanitized
`PLAYER_SEEK_FAILED` and can be retried. The provisional Flutter adapter uses
`video_player.seekTo`, whose reported position is not a measurement of the
first decoded or audible sample after the jump. AUD-003 and AV-005 therefore
remain device QA gates.

## End of media

`LoadedMedia.endEvents` reports natural completion only. The session turns a
completion from its current resource into `ENDED`, ignores duplicates and
events from a resource being released, and never starts the next playback on
its own. Seeking from `ENDED` moves to `PAUSED`; a separate Play command is
required to restart. This is exercised across 100 fake-resource endings.

