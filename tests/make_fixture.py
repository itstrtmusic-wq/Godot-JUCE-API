"""Generate a 100 ms, stereo 48 kHz WAV for integration tests."""
from pathlib import Path
import math
import struct
import wave
path = Path(__file__).resolve().parents[1] / 'demo/tests/tone.wav'
with wave.open(str(path), 'wb') as out:
    out.setparams((2, 2, 48000, 0, 'NONE', 'not compressed'))
    out.writeframes(b''.join(struct.pack('<hh', int(8192 * math.sin(2 * math.pi * 440 * i / 48000)), 0) for i in range(4800)))
print(path)
