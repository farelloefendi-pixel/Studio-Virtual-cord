# Essentia Offline Tempo Engine — Studio Chord Virtual

This is the first isolated C++ adapter for replacing only the offline BPM estimator in the FIX6 Lua extension. It does not replace the Lua interface, online providers, chord/key analysis, Studio Chord Virtual, transpose, or playback features.

## Engine decision

- Library: Essentia (C++).
- Main rhythm algorithm: `RhythmExtractor2013`.
- Beat tracking method: `multifeature`.
- Search range: 45–220 BPM, matching the supported range of the current FIX6 offline estimator.
- Required input: mono, 44,100 Hz, little-endian float32 PCM.
- Output: one JSON line containing BPM, confidence, beat timestamps, candidate estimates, and beat intervals.

Essentia documents that `RhythmExtractor2013` expects 44,100 Hz input and returns BPM, beat locations, confidence, estimates, and beat intervals. The multifeature method uses `BeatTrackerMultiFeature`.

## Important integration boundary

The current FIX6 decoder reduces audio to roughly 7,500 samples/second for its Lua analysis. That reduced stream must NOT be passed directly to `RhythmExtractor2013`: Essentia requires 44,100 Hz. The integration layer must decode/downmix/resample to mono 44,100 Hz before calling this adapter. This is deliberately not wired into Lua yet.

Before choosing the final bridge, verify whether the CSR/Jieshuo Lua runtime can safely execute a bundled native command or load a native `.so` from its own app storage. A Termux-built executable is not automatically executable from another Android app's private sandbox. Do not copy a Termux binary into the extension and assume it will work.

## Build

This adapter expects an already-built Essentia development library and headers. It is not a standalone replacement for Essentia.

```sh
cmake -S . -B build \
  -DESSENTIA_INCLUDE_DIR=/path/to/essentia/include \
  -DESSENTIA_LIBRARY=/path/to/libessentia.so
cmake --build build --config Release
```

For Android, Essentia itself must be built for the target Android ABI and compatible C++ runtime. The upstream Essentia FAQ documents a lightweight Android cross-build using KissFFT and its Android toolchain option. That documented path must be checked against the exact Essentia revision and current NDK before use.

## Input file format

A raw PCM file containing mono float32 little-endian samples at 44,100 Hz. No WAV header is included. Duration must be at least 8 seconds.

## Example invocation

```sh
./essentia_tempo /path/to/audio.f32
```

The program prints one JSON object to standard output. It does not print progress text into the JSON stream.

## Test plan before integration

1. Synthetic click tracks at known BPM values (for example 60, 75, 90, 100, 115, 120, 128, 140, 160, and 180).
2. Real songs with independently verified BPM, including the user's known 115 BPM reference track.
3. Half-time/double-time cases, tempo changes, intros without drums, silence, and short files.
4. Compare BPM error, confidence, processing time, peak memory, and repeatability against the current FIX6 offline result and the online provider.
5. Only after those tests pass, connect the adapter to Lua and preserve the old offline path behind a temporary fallback switch.

## Licensing checkpoint

Essentia is distributed under AGPLv3 for open-source/non-commercial use; the upstream project also describes a proprietary licence option. Before publishing a combined extension or distributing a binary, review the exact Essentia version and every dependency licence, and confirm whether AGPLv3 terms suit the intended distribution. Do not assume that a private GitHub repository changes the licence obligations for later distribution.
