# OwlListenKit

OwlListen 的 Apple 原生核心库，计划作为本地 Swift Package。详细路线见
[`docs/apple-native-migration.md`](../docs/apple-native-migration.md)。

## 职责

- Domain models 与版本化数据契约
- listening pack 导入、工作区和导出
- 词级 Diff 与后续错误分类
- 音频播放、切割和波形峰值
- M4B 元数据、章节、封面与播放状态
- Whisper 转写接口
- 包内记录与中央索引

## 依赖规则

- 不依赖 SwiftUI。
- API 优先使用值类型、protocol、`async/await` 和 `AsyncStream`。
- 文件格式必须有 fixture 和兼容测试。
- UI 更新只在 `OwlListenApp` 的 MainActor 边界发生。
- 初期使用一个 package target 和目录边界，确认需要后再拆 target。

## 计划目录

```text
Sources/OwlListenKit/
├── Domain/
├── Pack/
├── Diff/
├── Persistence/
├── Audio/
├── Waveform/
├── Transcription/
└── Audiobook/

Tests/OwlListenKitTests/
└── Fixtures/
```
