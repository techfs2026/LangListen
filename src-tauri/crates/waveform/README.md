# waveform

Reusable audio waveform decoding, peak-pyramid analysis, and viewport extraction.

The default `ffmpeg` feature provides file decoding:

```rust
use waveform::{ViewRange, Waveform, WaveformOptions};

let waveform = Waveform::open("audio.mp3", WaveformOptions::default())?;
let metadata = waveform.metadata();
let frame = waveform.query(ViewRange {
    start_sec: 0.0,
    end_sec: metadata.duration_secs,
    pixel_width: 1200,
})?;
```

The analysis layer can also consume PCM from another decoder:

```rust
use waveform::{AudioBuffer, BuildOptions, Waveform};

let audio = AudioBuffer::new(channels, sample_rate)?;
let waveform = Waveform::from_audio_buffer(audio, BuildOptions::default());
```

Implement `AudioDecoder` and call `Waveform::open_with_decoder` to integrate another
audio library without changing the waveform algorithm.
