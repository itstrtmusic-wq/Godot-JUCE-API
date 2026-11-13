# Build an audio interface entirely in GDScript

Copy the complete `demo/addons/juce_bridge` directory into your project, including the Windows DLL and `api` scripts. Godot discovers the `AudioSession` and `AudioTrack` classes when it imports the project. There is no EditorPlugin checkbox or autoload requirement. This API works with the existing multitrack (0.2) native engine; the API layer itself does not require C++ changes.

Attach this script to a Node. Set the exported WAV paths in the Inspector, or use absolute paths from your own file picker:

```gdscript
extends Node

@export_file("*.wav") var drums_path: String
@export_file("*.wav") var bass_path: String
var daw: AudioSession
var drums: AudioTrack
var bass: AudioTrack

func _ready() -> void:
    daw = AudioSession.new()
    daw.auto_initialize = false
    daw.audio_error.connect(_on_audio_error)
    daw.playback_finished.connect(_on_playback_finished)
    daw.position_changed.connect(_on_position_changed)
    add_child(daw)
    if not daw.initialize().is_empty():
        return

    drums = daw.add_track("Drums")
    bass = daw.add_track("Bass")
    drums.loaded.connect(func(path: String): print("Loaded: ", path))
    drums.levels_changed.connect(_on_drums_levels)
    if not drums.load_wav(drums_path).is_empty():
        return
    if not bass.load_wav(bass_path).is_empty():
        return

    drums.volume = 0.8
    bass.pan = -0.2
    bass.offset = 2.0
    daw.master_volume = 0.5
    daw.play()

func _on_audio_error(message: String) -> void:
    push_error(message) # Or show this in a label.

func _on_playback_finished() -> void:
    print("Reached the end of the session")

func _on_position_changed(seconds: float) -> void:
    pass # Update your playhead here.

func _on_drums_levels(stereo: Vector2) -> void:
    pass # stereo.x = left peak; stereo.y = right peak.
```

You can also leave `auto_initialize` enabled (the default). In that case, connect error signals **before** adding the session to the tree: it initializes during `_ready`. Create one session for an application. Freeing its Node automatically shuts down the device. `shutdown()` closes audio but preserves track objects and clips so you can call `initialize()` again. Avoid running the old raw-engine demo and another session at the same time.

## AudioSession

`AudioSession` is a Node. Add it to the scene tree for automatic initialization and notifications. It starts with no public tracks; `add_track()` uses the native engine's two preallocated slots first, then allocates more, up to 16. Native indices remain stable. Tracks are created by the session, not with `AudioTrack.new()`.

| Property | Meaning |
|---|---|
| `auto_initialize` | Initialize in `_ready`; default true |
| `master_volume` | Read/write linear gain, clamped to 0–1; default 0.5 |
| `audio_ready` | Read-only device initialization status |
| `state` | Read-only `&"stopped"`, `&"playing"` or `&"paused"` |
| `position`, `duration` | Read-only seconds, from the native engine |
| `levels` | Read-only master `Vector2` peaks before output ceiling |
| `tracks` | Read-only copied array of owned AudioTrack objects |

| Method | Result |
|---|---|
| `initialize()` | Empty string or error; can retry after failure |
| `shutdown()` | Close device; safe to repeat |
| `add_track(label = "")` | AudioTrack, or null with `audio_error` at the limit / unavailable engine |
| `play()` | Empty string or error; requires initialized device and loaded audio |
| `pause()`, `stop()` | Shared transport; pause preserves position after its fade, stop rewinds |
| `seek(seconds)` | Shared seek, clamped by native engine; nonfinite input emits error |
| `get_output_devices()` | PackedStringArray for the initialized backend |
| `select_output_device(name)` | Empty string or error |

| Signal | When it fires |
|---|---|
| `audio_error(message)` | A public operation fails, including a track load / invalid offset |
| `audio_ready_changed(ready)` | Successful initialization or device shutdown |
| `state_changed(state)` | Requested transport state changes; includes natural completion |
| `playback_finished()` | Playback reaches the session end, observed on a UI frame; explicit pause/stop/load/offset edits do not emit it |
| `track_added(track)` | A public track is created |
| `session_changed()` | Track added, audio loaded/cleared or clip offset changed |
| `device_changed(name)` | Output selection succeeds |
| `position_changed(seconds)` | Polled playhead changes |
| `levels_changed(stereo)` | Every processed UI frame, with latest master peaks |

## AudioTrack

| Property | Meaning |
|---|---|
| `track_name` | Read/write display name, independent of file name |
| `volume` | Read/write 0–1, default 1 |
| `pan` | Read/write -1 left to +1 right, default 0; stereo balance |
| `muted`, `solo` | Read/write booleans, default false |
| `offset` | Read/write clip start, seconds; valid range 0–86400; edits stop/rewind session |
| `duration` | Read-only source duration, excluding offset |
| `levels` | Read-only post-track / pre-master stereo peaks |
| `file_path` | Read-only last successfully loaded path, empty after clear |
| `index` | Read-only stable native track index |

Methods: `load_wav(path)`, `clear()`, and `set_offset(seconds)` return an empty string on success or an error string. Use `set_offset()` when you need to check its return value. Failed loads leave the previous clip and `file_path` intact. Loading and clearing stop/rewind the session; they retain mixer properties and offset.

Signals:

- `loaded(path)`: decoding succeeded. Runs synchronously during `load_wav`, after the clip and session state are updated.
- `load_failed(message)`: decoding/opening failed; the session also emits `audio_error`.
- `changed(property)`: a property changes, or file/offset operation succeeds. The property is a StringName, such as `&"volume"`, `&"offset"`, or `&"file_path"`.
- `levels_changed(stereo)`: latest peaks, forwarded on the session's UI frame.

Nonfinite volume and pan values are ignored; finite values are clamped. There is no track deletion yet; use `clear()` and reuse the same object. Keep the session alive while using its tracks. A retained track cannot keep a deleted session alive: it holds a weak reference, returns zero duration/meters afterward, and reports load/edit errors safely.

## What callbacks mean here

These are **main-thread Godot signals**, not execution inside JUCE's audio callback. Call all API methods from the main thread. The session polls native atomics once per `_process`, so meters and playback completion follow Godot's UI frame rate. Signals require the session to be in the tree and processing; if you pause its processing, notifications resume when processing resumes. A natural completion is emitted at most once per armed playback. Seeking to the end while playing counts as completion.

Property/error/file-load signals are synchronous main-thread notifications. WAV decoding is still synchronous and may freeze the UI briefly. Playback state reports the requested state, while audible pause/stop/seek transitions use native 5 ms ramps. Do not use a signal, Timer or `_process` to schedule sample-accurate notes or produce individual audio samples. Those features need dedicated native scheduling/processing APIs.

The existing limits still apply: one clip per track, 256 MiB total decoded audio, WAV-only loading, no recording/MIDI/effect graph yet. `res://` and `user://` loose-file paths are globalized automatically, but JUCE cannot read files embedded in an exported PCK; extract them to `user://` or use external files. Use this layer consistently: mixing direct `JuceEngine` control with cached AudioTrack properties is not supported.

The multitrack demo uses this API in `demo/main.gd`. The original raw `JuceEngine` interface remains available for advanced integrations.

## Save and reopen a session

```gdscript
# These return an empty string on success and emit audio_error on failure.
var error = daw.save_project("user://my-song.gjproject")
if not error.is_empty():
    push_error(error)

# Existing track handles are replaced on successful load. Rebuild your UI or
# retrieve fresh handles inside this signal, rather than reusing old ones.
daw.project_loaded.connect(func(path: String):
    print("Opened ", path)
    for track in daw.tracks:
        print(track.track_name, " ", track.file_path))
daw.load_project("user://my-song.gjproject")
```

`save_project(path)` saves track names/order, WAV references, offsets, volume, pan, mute, solo and master volume in versioned JSON. It does not change transport or copy audio. Files beneath the project directory use relative references; other audio keeps absolute references. Keep the WAVs available, or move the project folder together with its referenced audio. Projects are not self-contained audio bundles. Playback position, playing/paused state and audio-device preferences are not serialized.

`load_project(path)` validates the entire project and decodes its referenced WAVs in an unopened staging engine before replacing your session. A malformed project, missing/invalid WAV, or decode limit failure leaves existing track objects and audio untouched. A successful load starts stopped at zero and replaces all track objects. Old retained handles are detached, as if their session were gone. Listen to `project_loaded(path)` and reacquire `daw.tracks`; restored tracks do not individually emit `track_added` or `loaded`. `session_changed` also fires after the successful replacement. `project_saved(path)` fires only after a successful save.

Loading is synchronous and may pause the interface. Staging can roughly double decoded-audio memory while both sessions exist, plus temporary decoder buffers. If audio is initialized, the loader closes the old device only after decoding succeeds, opens the staged engine, and reapplies the selected output. A device-open failure attempts to restore the previous engine/device and reports an error; its tracks remain available, but transport is stopped. If restoration also fails, `audio_ready` becomes false and `audio_ready_changed(false)` is emitted. Call `initialize()` to retry. Hardware activation must still be tested on Windows.

Both project methods accept an absolute path, `res://` loose-file path, or `user://` path. Use a writable location such as `user://` in exports. The `.gjproject` extension is conventional; the API checks the actual format/version. Project files are limited to 1 MiB, 16 tracks, and valid mixer/offset ranges. Saving writes a sibling temporary file, flushes it and renames it over the destination; failures before replacement preserve the old file. This does not guarantee recovery from an OS crash or power loss.

## Which JUCE features can GDScript call today?

Only the bindings provided by this add-on are callable; importing JUCE does not expose every JUCE C++ class automatically.

| Feature | Available through the current API |
|---|---|
| Windows output devices | Initialize/shutdown, list/select WASAPI outputs |
| Playback and mixing | Mono/stereo WAVs, up to 16 tracks, master/track gain, balance, mute/solo |
| Timeline and transport | Clip offsets, shared play/pause/stop/seek, position/duration |
| Notifications | Main-thread loading/error/state/completion/meter signals |
| Project files | Save/load through GDScript; this is an add-on feature, not a JUCE callback |
| Input recording, MIDI, VST3 hosting | Not yet exposed |
| JUCE DSP/effect processors | Not yet exposed; no GDScript real-time audio processing callback |
| JUCE GUI components or arbitrary JUCE classes | Not exposed; build the interface with Godot |

We can extend this surface with dedicated GDScript-facing objects as those engine capabilities are implemented.
