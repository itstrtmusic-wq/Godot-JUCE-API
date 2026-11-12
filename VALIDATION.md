# Validation of the initial prototype

Validated in this session on Linux x86_64 with GCC 14.2, CMake 4.4.4, JUCE 8.0.6, godot-cpp godot-4.3-stable and Godot 4.6.3.

- Native debug build: passed, including link-time checking for unresolved symbols.
- Godot headless editor import: passed without errors or warnings.
- Native registration, WAV decoding/duration, failed-load recovery, nonfinite gain handling and repeated engine cleanup: passed (`demo/tests/engine_test.gd`).
- Demo scene startup and shutdown: passed in headless mode.
- `git diff --check`: passed.

This environment has no Windows toolchain/audio devices. The Linux check used `-DCMAKE_CXX_FLAGS="-DJUCE_ALSA=0 -DJUCE_JACK=0"` because ALSA development headers are absent. It does not test hardware playback, callback timing, stereo output, meter correctness, Windows compilation or WASAPI. The Windows workflow has been authored but not executed here. Godot 4.3 compatibility is targeted by the bindings and the Windows workflow; the local Godot run used 4.6.3.

Windows build and manual acceptance steps are in README.md. Recording, multitrack playback and VST3 hosting are not implemented in this first milestone.
