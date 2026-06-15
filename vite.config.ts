import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "path";

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: [
      {
        find: "@owllisten/waveform-react/tauri",
        replacement: path.resolve(__dirname, "./packages/waveform-react/src/tauriBackend.ts"),
      },
      {
        find: "@owllisten/waveform-react",
        replacement: path.resolve(__dirname, "./packages/waveform-react/src/index.ts"),
      },
      { find: "@", replacement: path.resolve(__dirname, "./src") },
    ],
  },
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
    watch: { ignored: ["**/src-tauri/**"] },
  },
});
