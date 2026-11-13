# Godot JUCE Audio Bridge

A Windows x64 GDExtension for building a standalone audio application with a Godot interface and JUCE device output. The current version includes a multitrack mixer, basic timeline, and a GDScript API. It is an early DAW foundation; recording, MIDI and plug-in hosting are still to come.

## GDScript API — no C++ required for your interface

Use `AudioSession` and `AudioTrack` to control the engine with properties and Godot signals:

```gdscript
var daw = AudioSession.new()
add_child(daw) # Automatically initializes the audio device.
var drums = daw.add_track("Drums")
if drums and drums.load_wav("C:/Audio/drums.wav").is_empty():
    drums.volume = 0.8
    drums.pan = -0.2
    daw.playback_finished.connect(func(): print("Finished"))
    daw.play()
```

See **[the GDScript API guide](docs/GDSCRIPT_API.md)** for error handling, device selection, all properties/signals, and a complete starter script. The demo now uses this layer. Copy the whole add-on, including its `api` folder and DLL. Existing multitrack DLLs remain compatible; the GDScript layer adds no native audio callbacks. Audio runs in C++, and UI notifications arrive on Godot's main thread.

## Build on Windows

Install **Godot 4.3 or newer (standard, single precision, x64)**, **Visual Studio 2022** with **Desktop development with C++** and a Windows SDK, **CMake 3.22+**, **Git**, and **Python 3** (on PATH).

From PowerShell in this repository:

```powershell
cmake -S . -B build -A x64 -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release --parallel 2
```

CMake downloads JUCE **8.0.6** and godot-cpp **godot-4.3-stable**. The first build takes several minutes. Output is `demo/addons/juce_bridge/bin/juce_bridge.dll`. Close Godot before rebuilding: hot reload is disabled. Rebuild the DLL when upgrading from the single-file prototype; the new demo checks for the updated API. Debug and Release share one filename; build one configuration at a time.

The bridge builds only the Godot class bindings it uses; set `-DBRIDGE_MINIMAL_BINDINGS=OFF` if you extend it to use other engine classes.

## Try the multitrack demo

Open `demo/project.godot` in Godot and press **F5**.

1. Select an output device, or keep the system default.
2. Open a mono/stereo WAV on each of the two initial tracks.
3. Press **Play**. Both tracks share one audio clock and transport.
4. Click the timeline or use the transport slider to seek. Click a clip without dragging to seek there.
5. Drag a clip horizontally, or set its **Start (s)** field, to place it later in the session.
6. Adjust each track's volume, stereo balance/pan, mute and solo. Add tracks up to the limit of 16.

Loading, clearing and moving clips stops and rewinds the session. Failed loads preserve the existing audio. Pause preserves position after a short fade; Stop fades then rewinds. Playback stops at the last loaded clip's end, including its offset. Pressing Play at the end restarts the session. Several soloed tracks play together; mute takes precedence over solo. Soloing an empty track can silence other tracks.

Track meters show stereo peaks after the track controls and before the master. Master meters show peaks before the output safety ceiling. A clipping message means the summed signal exceeded 1.0: lower the master or track volumes. The output ceiling is hard clipping protection, not a transparent limiter. Start with the default master gain of 50%.

Use **Save project…** and **Open project…** to save/reopen `.gjproject` sessions. Track names, audio references, offsets, volume/pan/mute/solo and master volume are restored. WAVs are referenced, not embedded; keep them available. Opening a project stops/rewinds transport and replaces track handles. Malformed projects and missing WAVs leave the loaded session intact. See the API guide for staging-memory and device-reopen behavior.

The Windows backend is JUCE's default WASAPI implementation. The device menu lists outputs for that backend. Backend selection and ASIO are not included.

## Use in another Godot project

Copy `demo/addons/juce_bridge` into your project's `addons` directory, including the compiled DLL. There is no EditorPlugin checkbox: Godot loads the GDExtension automatically. Create **one engine per application**, with multiple tracks inside it:

```gdscript
var engine = ClassDB.instantiate("JuceEngine")

func _ready():
    var error = engine.initialize() # Empty string means success.
    if not error.is_empty():
        push_error(error)
        return
    error = engine.load_track_wav(0, "C:/Audio/drums.wav")
    if not error.is_empty():
        push_error(error)
        return
    error = engine.load_track_wav(1, "C:/Audio/bass.wav")
    if not error.is_empty():
        push_error(error)
        return
    engine.set_track_offset(1, 2.0)
    engine.set_track_volume(0, 0.8)
    engine.set_track_pan(1, -0.25)
    engine.set_volume(0.5)
    engine.play()

func _exit_tree():
    engine.shutdown()
```

JUCE needs absolute filesystem paths. In the editor, `ProjectSettings.globalize_path("res://music.wav")` works for loose files. In exported applications JUCE cannot read resources inside Godot's PCK; use external WAVs or extract packaged files to `user://` first. Call all API methods on Godot's main thread.

### Low-level native API

Track indices are zero-based and stable. Two empty tracks exist initially; there is no track deletion yet. Use `clear_track` to remove a clip and reuse a track.

| Method | Result / behavior |
|---|---|
| `initialize()` / `shutdown()` | Open default stereo output / close device; shutdown is safe to repeat |
| `get_output_devices()` | Output names for active backend |
| `select_output_device(name)` | Empty string on success, otherwise error |
| `get_track_count()` | Initially 2; at most 16 |
| `add_track()` | New track index, or -1 at limit |
| `load_track_wav(track, absolute_path)` | Decode/replace one clip; empty string or error |
| `load_wav(absolute_path)` | Backwards-compatible alias for loading track 0 |
| `clear_track(track)` | Remove clip, retaining track controls and offset; empty string or error |
| `set_track_offset(track, seconds)` | Offset between 0 and 86400 seconds; stops/rewinds; empty string or error |
| `get_track_offset(track)` / `get_track_duration(track)` | Clip start / source duration, in seconds |
| `set_track_volume(track, gain)` | Linear gain, clamped to 0–1 |
| `set_track_pan(track, pan)` | -1 left, 0 center, +1 right; attenuates the opposite channel, center unity |
| `set_track_mute(track, muted)` / `set_track_solo(track, solo)` | Smoothed audibility controls |
| `get_track_levels(track)` | `Vector2` of latest-block linear stereo peaks |
| `play()` / `pause()` / `stop()` | Shared transport, with 5 ms ramps |
| `seek(seconds)` | Seek all tracks together; clamped to session length; playing seeks fade out/in |
| `get_position()` / `get_duration()` | Shared playhead / end of last loaded clip, seconds |
| `is_playing()` | Requested playback state; pause can have a short audible fade tail |
| `set_volume(gain)` / `get_levels()` | Master gain 0–1 / pre-ceiling stereo peaks |

Initialization returns an empty string or error. Invalid track indices return errors for clip/offset operations, zero for numeric getters and levels, and are ignored by mixer setters. Nonfinite gain/pan and seek requests are ignored. Volume/pan controls are clamped. Transport position reflects completed audio processing, so a seek or Stop appears after processing its short fade; it is not a synchronous position setter. Without an active device, transport commands have no callback to process them.

## Audio design and limits

JUCE owns clip output; Godot's audio server is not used for these tracks. A shared C++ renderer advances time once per output sample and derives each clip's local position from its offset and source rate. It uses 32-tap, 256-phase windowed-sinc resampling with a downsampling lowpass; this is finite-quality conversion, not an offline mastering resampler. Equal-rate integer positions use a direct sample path. Mono is duplicated to stereo; stereo pan acts as balance, not a stereo-to-mono panner.

The callback makes no Godot/GDScript calls, performs no file I/O or buffer allocation, and communicates through lock-free atomics. Track gains, balance, master volume, mute/solo and transport transitions are smoothed over approximately 5 ms. Clip starts and ends have 5 ms fades. These deliberately soften transients at file boundaries. Seeks briefly fade the old position out before jumping and fading the new position in.

All clips are decoded into memory: at most 16 tracks, one clip per track, 33,554,432 frames per clip, and 256 MiB total decoded audio. Temporary decoding buffers can make peak memory usage higher. Loading and structural changes detach the callback before altering its buffers; these operations are synchronous, may freeze the interface, and do not have a playback fade-out. No disk streaming, waveform display, clip trimming, looping, recording, MIDI or VST3 hosting is implemented yet. The timeline shows clip rectangles with file names and seconds, not waveforms or musical bars/beats. Metering polls latest-block peaks and can miss short transients.

## Validation

After building:

```powershell
ctest --test-dir build -C Release --output-on-failure
python tests/make_fixture.py
godot --headless --path demo --editor --import --quit
godot --headless --path demo --script res://tests/engine_test.gd
godot --headless --path demo --script res://tests/ui_test.gd
godot --headless --path demo --script res://tests/api_test.gd
godot --headless --path demo --script res://tests/project_test.gd
```

The C++ test executes the same renderer as the device callback, without hardware. It checks summing, a shared clock, clip offsets/gaps, gain/pan, mute/solo, pause/stop/seek ramps, EOF/restart, resampling, alias suppression and the output ceiling. Godot tests check the native API, WAV/error handling, track limits, controls and clip dragging. The Windows workflow runs these tests and uploads the demo with its DLL.

Manual Windows acceptance: load two WAVs, check synchronized playback and meters, offset one clip, seek while playing and paused, test mute/solo/pan, switch devices, load 44.1 kHz and 48 kHz material together, and close during playback. Automated tests do not establish audio-device timing, drop-out performance or Windows output behavior. See VALIDATION.md for actual local results.

## Licensing

This repository retains its Apache-2.0 license for its own code. JUCE and godot-cpp have separate licenses. JUCE 8 uses JUCE commercial licensing or AGPLv3; review which route applies to your distribution. This repository's Apache license does not grant a JUCE commercial license. No ASIO SDK is bundled.
