# CWhisper

This target vendors the CPU implementation of whisper.cpp 1.8.3 and ggml 0.9.5.
The source was copied from the existing `whisper-rs-sys` build used by the
legacy Tauri application.

Upstream:

- https://github.com/ggml-org/whisper.cpp
- whisper.cpp commit bundled by whisper-rs-sys 0.16.0
- ggml commit `c02de38`

The upstream MIT license is preserved at
`third_party/whisper.cpp/LICENSE`.

Only the CPU and Accelerate backends are compiled. The Swift-facing API is kept
in `include/owl_whisper_bridge.h`.
