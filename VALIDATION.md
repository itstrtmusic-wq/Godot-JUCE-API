# Validation of multitrack milestone (0.2)

Validated locally on Linux x86_64 with GCC 14.2, CMake 4.4.4, JUCE 8.0.6 and godot-cpp godot-4.3-stable.

Passed:

- Native debug build, with link-time checking for unresolved symbols.
- CTest renderer tests: two-track summing, shared-clock advancement, mono/stereo mapping, stereo balance, gain, mute/solo, post-fader metering, clip offsets and gaps, pause/stop/seek fades, EOF/restart, 44.1-to-48 kHz conversion, downsampling alias suppression and pre-ceiling metering/output ceiling.
- Renderer exercised under AddressSanitizer and UndefinedBehaviorSanitizer without reported errors.
- Godot 4.3 and 4.6.3 headless imports without script errors.
- Godot API tests on both versions: WAV/error recovery, source/session durations, offsets and invalid values, track limits and engine lifetime.
- Godot UI tests on both versions: scene initialization, two track rows, WAV loading, adding a track, timeline offset synchronization, simulated clip dragging and cleanup.
- Demo startup/shutdown in Godot 4.6.3 headless mode.
- `git diff --check`.

The Linux build used `-DCMAKE_CXX_FLAGS="-DJUCE_ALSA=0 -DJUCE_JACK=0"` because ALSA development headers are absent. Offline tests call the exact mixer used by the JUCE callback but do not exercise an audio device. They do not establish hardware timing, drop-out performance, Windows compilation or WASAPI output. UI tests are headless and do not establish visual appearance on Windows.

The Windows workflow now includes renderer and Godot integration tests; its current run has not been verified here. Manual Windows playback steps are in README.md. The user reported that the earlier single-file prototype worked on Windows; the multitrack update still needs that platform acceptance check.

## GDScript API milestone

The new AudioSession/AudioTrack layer was tested locally on Godot 4.3 and 4.6.3 with the existing multitrack native library. API tests cover native WAV loading through Godot paths, relative-path validation, metadata recovery after failure, offset editing, copied track collections, property routing/clamping, recoverable initialization failure, device selection errors, EOF notification exactly once, suppression of EOF on explicit pause/stop, main-thread notification delivery, meter signals, track limits, repeated shutdown, and tracks retained after their session is deleted. Device/EOF transitions use a controlled fake native boundary; actual file operations use the real extension. These tests do not claim live hardware callback testing.

Both Godot versions passed the demo interaction test after its conversion to the public GDScript API. The existing native API tests, C++ mixer tests, and Godot 4.6.3 headless demo startup also passed. No native audio source changed in this milestone. The Windows workflow now includes the new API test, but its run has not been verified here.

## Project save/load milestone

Project and updated demo-interaction tests passed on Godot 4.3 and 4.6.3. They cover round-tripping ordered tracks, names (including empty names), audio references, empty tracks, offsets, mixer values and master gain; relative references for audio beneath the project folder; successful file replacement; failed-save preservation; malformed/oversized JSON; unsupported versions; invalid types/ranges and excessive track counts; missing/invalid WAVs; preservation of the current native engine and track identity on preflight failure; detached old handles after success; empty projects; and UI reconstruction of restored faders/toggles/master volume. Controlled device doubles exercise activation failure, successful rollback, failed rollback/readiness reporting, and successful activation. Those device cases do not establish actual WASAPI behavior.

The existing GDScript API and native API tests passed after the changes. No native audio source changed, so the existing multitrack DLL remains compatible. Windows filesystem replacement, physical device reopening and playback during project loading remain platform acceptance checks; the Windows workflow now includes project tests.

## Native EQ milestone (0.3)

The native library built successfully and both CTest targets passed. EQ tests measure low/mid/high cut and boost responses at 44.1/48/96 kHz, flat transparency, stereo isolation, settled dry bypass, edits during bypass, reset behavior and rapid-control stability at 8/22.05/44.1/48/96 kHz. Mixer tests confirm that the EQ processes only its own track before summing and that bypass restores the dry mix. The EQ test also passed AddressSanitizer and UndefinedBehaviorSanitizer checks.

Godot 4.3 and 4.6.3 passed the GDScript API, project and UI integration tests, covering gain clamps, ignored nonfinite values, effect lookup, bypass/reset routing, per-band UI controls, EQ project round trips, old-handle safety, invalid EQ rejection and version 1 migration to neutral settings. Imports completed without script errors. Windows compilation, actual WASAPI playback and perceptual assessment of automation/bypass transitions remain acceptance checks. Unlike the prior script-only milestones, this change requires rebuilding the DLL.
