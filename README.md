# Godot JUCE Audio Bridge

A first Windows x64 GDExtension for building a standalone audio application with a Godot interface and a JUCE audio engine. This is a single-file playback prototype, not yet a DAW.

## Build on Windows

Install **Godot 4.3 or newer (standard, single precision, x64)**, **Visual Studio 2022** with **Desktop development with C++** and a Windows SDK, **CMake 3.22+**, **Git**, and **Python 3** (available on PATH).

From PowerShell in this repository:

```powershell
cmake -S . -B build -A x64 -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release --parallel 2
```

The bridge builds only the Godot class bindings it uses; set `-DBRIDGE_MINIMAL_BINDINGS=OFF` if you extend it to use other engine classes.

CMake downloads JUCE **8.0.6** and godot-cpp **godot-4.3-stable**. The first build takes several minutes. Output is `demo/addons/juce_bridge/bin/juce_bridge.dll`. Close Godot before rebuilding: hot reload is disabled. Debug and Release use the same output filename; build one configuration at a time.

Open `demo/project.godot` in Godot and press **F6** on `main.tscn` or **F5**. Select an output, open a mono/stereo WAV, and press Play. Pause preserves the position; Stop rewinds. Play after reaching the end restarts the clip. Start with the default volume of 50%.

The current Windows backend is JUCE's default WASAPI implementation. The device menu lists outputs for that backend. Backend selection and ASIO are not included.

## Use in another Godot project

Copy `demo/addons/juce_bridge` into your project's `addons` directory, including the compiled DLL. There is no EditorPlugin checkbox: Godot loads the GDExtension automatically. Instantiate one engine for your application, and keep it alive while using audio:

```gdscript
var engine = ClassDB.instantiate("JuceEngine")

func _ready():
    var error = engine.initialize() # empty string means success
    if not error.is_empty():
        push_error(error)
        return
    error = engine.load_wav(ProjectSettings.globalize_path("res://music.wav"))
    if error.is_empty():
        engine.set_volume(0.5)
        engine.play()

func _exit_tree():
    engine.shutdown()
```

For exported applications use an external WAV's absolute filesystem path. JUCE cannot read resources inside Godot's PCK; packaged audio needs a future stream bridge or extraction to `user://`. Call all engine methods on Godot's main thread. Do not create one engine per track: this version opens one audio device per engine.

### API

| Method | Result / behavior |
|---|---|
| `initialize()` | Opens default stereo output; empty string or error |
| `get_output_devices()` | Names for the active backend |
| `select_output_device(name)` | Empty string or error |
| `load_wav(absolute_path)` | Decodes and replaces clip; empty string or error. Failed loads preserve the old clip. |
| `play()` / `pause()` / `stop()` | Transport commands |
| `set_volume(linear_gain)` | Clamps finite values to 0–1; ignores nonfinite values |
| `get_position()` / `get_duration()` | Seconds |
| `is_playing()` | Playback state |
| `get_levels()` | `Vector2` of latest audio-block linear peaks, before UI decay |
| `shutdown()` | Stops output and closes device; safe to repeat |

## Audio design and current limits

JUCE owns device output; Godot's audio server is not used for this clip. The audio callback makes no Godot/GDScript calls, performs no file I/O or buffer allocation, and uses atomic transport, gain and meter values. Clip replacement first removes the callback, waiting for active processing before replacing memory. Device changes and WAV decoding run synchronously on the main thread and may briefly freeze the interface. The callback clock, rather than UI frames, advances playback.

The prototype decodes a whole WAV into memory, supports one mono/stereo clip up to 33,554,432 frames (at most 256 MiB decoded), uses linear interpolation for sample-rate conversion, and ramps volume over each block. This is not production-quality resampling. Transport commands take effect at block boundaries, without fades. Stop/pause/file replacement can click; meters are latest-block peaks and may miss short transients between UI polls.

Next milestones: high-quality disk streaming, a shared multitrack graph, sample-accurate transport and clip scheduling, recording, project persistence, MIDI, then VST3 hosting. Native plug-in editor windows and ASIO will need separate Windows integration work.

## Validation

Generate the deterministic WAV fixture, import the project, and run the integration tests after building:

```powershell
python tests/make_fixture.py
godot --headless --path demo --editor --import --quit
godot --headless --path demo --script res://tests/engine_test.gd
```

These tests cover extension registration, valid WAV loading, duration, invalid-file recovery, gain validation, and engine lifetime without requiring audio hardware. They do not establish working Windows audio playback. Manual Windows acceptance: select an output, play a WAV, check stereo meters, pause/resume, stop/restart, switch outputs, load another file, and close during playback. Check both 44.1 kHz and 48 kHz files.

A Windows GitHub Actions build and integration-test workflow is included; it has not been run merely by creating it. Linux entries in the extension descriptor support development checks, but Windows is the target platform. See VALIDATION.md for the actual local results.

## Licensing

This repository retains its Apache-2.0 license for its own code. JUCE and godot-cpp are separate dependencies with their own licenses. JUCE 8 uses JUCE commercial licensing or AGPLv3; review which route applies to your distribution. This repository's Apache license does not grant a JUCE commercial license. No ASIO SDK is bundled.
