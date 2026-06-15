# @owllisten/waveform-react

Headless waveform session state and a WebGL React canvas.

```tsx
import {
  WaveformCanvas,
  useWaveform,
} from "@owllisten/waveform-react";
import { createTauriWaveformBackend } from "@owllisten/waveform-react/tauri";

const backend = createTauriWaveformBackend();
const waveform = useWaveform({ backend });
```

Implement `WaveformBackend` to use the React layer with a non-Tauri host.
