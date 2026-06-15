# OwlListen Apple 原生迁移计划

## 1. 迁移目标

将现有 Tauri 桌面应用逐步迁移为 macOS 原生应用，同时保持旧版本可运行，
直到原生版本通过功能等价验收。

根目录职责：

- `OwlListenApp/`：SwiftUI/AppKit 应用、页面、系统权限、快捷键和依赖装配。
- `OwlListenKit/`：Swift Package，承载领域模型、数据包、Diff、存储、音频、
  波形、转写和有声书能力。

首期只支持 macOS。代码设计为可复用，但不为了尚未开始的 iOS 版本提前增加
复杂抽象。

## 2. 核心原则

1. **按垂直功能迁移，不按技术层整体重写。**
   每个阶段都交付一条可操作、可验收的用户流程。
2. **先冻结数据契约，再重做界面。**
   `metadata.json`、标签文件、进度数据和未来的 `records.json` 必须有版本号、
   fixture 和兼容测试。
3. **OwlListenKit 不依赖 SwiftUI。**
   业务能力可以被单元测试，也能被未来的 macOS/iOS App 共同使用。
4. **原生优先，不追求逐行翻译 Rust/TypeScript。**
   优先使用 Swift、AVFoundation、Accelerate、Core Graphics/Metal、SQLite。
5. **Tauri 版本是迁移期间的行为基准。**
   同一输入在两端对照，原生版本验收后才停止维护对应旧功能。
6. **避免“顺便重做 0.2.0”。**
   先达到 0.1.x 功能等价，再实施行为记录、弱词、SRS 和统计等新需求。

## 3. 目标技术方案

### OwlListenApp

- SwiftUI：窗口、导航、表单、列表、状态展示。
- AppKit bridge：文件拖放、精细键盘事件、必要的窗口行为。
- Observation / Swift Concurrency：界面状态和异步任务。
- `Commands` / keyboard shortcuts：复刻现有全键盘操作。
- 权限与系统集成：麦克风、文件访问、Finder 定位、应用生命周期。

### OwlListenKit

初期保持一个 Swift Package target，按目录隔离职责；只有出现明确的编译边界或
复用需求时再拆成多个 target。

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
```

建议映射：

| 现有能力 | Apple 原生实现候选 |
|---|---|
| React 状态与页面 | SwiftUI + `@Observable` feature model |
| Tauri command/event | Swift 方法、`AsyncStream`、delegate/callback |
| cpal 播放 | AVAudioEngine / AVAudioPlayerNode |
| M4B 常规播放 | AVPlayer；能力不足时再下沉 AVAudioEngine |
| FFmpeg 解码/切割 | AVAssetReader / AVAssetExportSession / AVAudioFile |
| atempo 变速 | AVAudioUnitTimePitch 或 AVPlayer time pitch algorithm |
| Canvas/WebGL 波形 | SwiftUI Canvas、Core Graphics；性能不足再使用 Metal |
| 峰值计算 | AVAssetReader + Accelerate，磁盘峰值缓存 |
| Whisper | whisper.cpp 的 C/C++ 接口，经 Swift 包装 |
| JSZip / Rust zip | Foundation Archive 能力或经过评估的 ZIP 库 |
| JSON 进度文件 | Codable + 原子写入 |
| 中央索引 | SQLite repository；包内 JSON 仍是真相源 |

Apple Speech 不应直接替代 Whisper：OwlListen 的产品约束是离线与可控模型，
必须先验证系统版本、语言和离线可用性后才能作为可选后端。

## 4. 必须先冻结的兼容契约

迁移开始前建立 `OwlListenKit/Tests/OwlListenKitTests/Fixtures/`，至少包含：

- 一个短 MP3/WAV 标注样本。
- 一个带章节和封面的 M4B。
- 一个无章节 M4B。
- 一个当前格式的 listening pack ZIP。
- 一份 Audacity 标签文件。
- 中英文、标点、空文本和重复词的 Diff 用例。
- 损坏文件、缺少片段、旧版本 metadata 的失败样本。

需要明确：

- `metadata.json` 当前 `version` 的含义及升级策略。
- 时间统一使用秒，序列化为 `Double`。
- 片段索引、文件名和排序规则。
- Diff 的 tokenization、准确率分母和插入/删除语义。
- 有声书进度是“章节内秒数”，不是全书绝对秒数。
- 写文件使用临时文件 + replace，避免崩溃留下半个 JSON。

## 5. 分阶段路线

### M0：基线与工程骨架

产出：

- 用 Xcode 创建 `OwlListenApp` macOS App。
- 将 `OwlListenKit` 创建为本地 Swift Package，并由 App 引用。
- 建立单元测试、UI 测试和 fixture。
- 截图并记录三个现有工作流的关键行为与快捷键。
- 给数据格式补充版本和兼容性说明。

验收：

- App 可启动并显示原生首页。
- App target 不包含业务实现，Kit 不依赖 SwiftUI。
- CI 或本机命令可以独立运行 Kit tests。

### M1：精听复习最小闭环

迁移顺序：

1. `PackMetadata`、`ListenSegment`、状态模型。
2. ZIP 导入、metadata 校验、片段读取。
3. 短音频播放、暂停、重播、循环。
4. 听写输入、词级 Diff、正确率。
5. done/flagged 状态、片段导航和快捷键。

暂不包含：语音输入、历史记录、跨数据包统计。

验收：

- 同一 ZIP 在 Tauri 和原生版显示相同片段顺序与文本。
- 固定 Diff fixture 的操作序列和准确率完全一致。
- 键盘可以完成完整复习流程。

选择它作为第一条链路，是因为它覆盖模型、文件、播放和 UI，但不依赖最复杂的
长音频波形与流式播放。

### M2：有声书

迁移顺序：

1. M4B 元数据、章节、封面解析。
2. 最近书架和进度恢复。
3. 播放、暂停、章节 seek、上一章/下一章。
4. 0.5x-1.75x 变速不变调。
5. 章末自动续播、错误状态、定时持久化。

先用 AVPlayer 做技术验证；若章节边界、精准 seek、变速或事件时序无法满足现有
行为，再将播放内核替换为 AVAudioEngine。不要一开始照搬 Rust 的三线程结构。

验收：

- fixture M4B 的标题、作者、章节边界和封面正确。
- 暂停时切章，UI 与恢复播放位置正确。
- 切速率前后进度不跳变。
- 退出重开后恢复到允许误差内的位置。

### M3：初次精听的播放与波形

迁移顺序：

1. 长音频打开与元数据读取。
2. 后台生成多分辨率峰值，并落盘缓存。
3. 波形缩放、滚动、播放头和时间轴。
4. 拖拽框选、边界调整、选中自动 AB 循环。
5. 标签新增、编辑、删除、导入和导出。

验收：

- UI 主线程不执行解码和峰值计算。
- 数小时音频不长期保留完整 PCM。
- 缩放/拖动流畅，播放头与可闻位置保持可接受误差。
- 相同标签文件往返后时间和文本不丢失。

### M4：切割、Whisper 与数据包导出

迁移顺序：

1. 按标签边界切割为 16kHz 单声道片段。
2. 集成 whisper.cpp，封装模型加载、缓存、取消和进度。
3. 生成 metadata 与片段目录。
4. 构建 ZIP，并支持 Finder 定位。
5. 录音、麦克风权限、录音转写。

验收：

- 导出的 ZIP 可以被旧 Tauri 版本导入。
- 切割起止点、命名、排序与 metadata 一致。
- 转写任务不会阻塞 UI，可取消，错误可恢复。
- Whisper 模型不被打进 Git；发布方式和首次下载策略单独确定。

### M5：0.1.x 功能等价与切换

- 建立逐项 parity checklist。
- 对三个工作流执行回归测试和性能测试。
- 完成沙盒、签名、公证、权限描述和发布构建。
- 原生版本连续使用一个稳定周期后，再决定是否归档 Tauri 代码。

退出条件：

- 没有阻断日常使用的数据兼容问题。
- 旧数据包可以读取，新数据包可回退读取。
- 崩溃、播放、seek、休眠/唤醒、音频设备切换经过测试。

### M6：实施 0.2.0 训练系统

在原生 0.1.x 稳定后实施：

1. 包 UUID、工作区目录和 zip 导入/导出。
2. 包内 `records.json` 原始行为记录。
3. SQLite 可重建中央索引。
4. 错误子分类、历史反馈和标准文本纠错。
5. 标签聚合、弱词、跨包练习。
6. SRS 与统计面板。

这一步不应与 UI 迁移混在一起，否则无法判断问题来自平台迁移还是产品模型变化。

## 6. 测试策略

- **Domain tests**：Codable、Diff、标签排序、进度换算。
- **Contract tests**：旧数据可读、新数据向后兼容、损坏输入失败方式明确。
- **Audio integration tests**：duration、seek、segment 边界、speed、chapter end。
- **Golden tests**：波形峰值和 Diff 结果使用固定 fixture 对照。
- **UI tests**：三个主流程及核心快捷键。
- **Manual matrix**：Intel/Apple Silicon（若仍支持）、不同采样率、蓝牙设备切换、
  睡眠唤醒、文件被移动、权限拒绝。

浮点音频测试使用明确容差，不比较逐样本完全相等。

## 7. 风险与控制

| 风险 | 控制方式 |
|---|---|
| AVFoundation 对部分 M4B/章节行为与 FFmpeg 不同 | 先做 fixture spike，再承诺实现方案 |
| Whisper C++ 集成、模型体积和发布复杂 | 独立里程碑，不与 UI 绑定 |
| 波形一次重写过大 | 峰值服务、渲染、交互分三步 |
| SwiftUI 键盘/窗口细节受限 | 允许局部 AppKit bridge |
| 迁移期间两套实现漂移 | 旧版冻结新功能，fixture 双端对照 |
| 为未来 iOS 过度设计 | macOS-first，Kit 只保留自然可复用边界 |

## 8. 建议节奏

不要用日历时间作为主要承诺，使用里程碑退出条件。个人业余开发可采用：

- 每次只迁移一个用户流程。
- 每个 PR 同时包含实现、fixture/测试和 parity checklist 更新。
- 新原生功能稳定前，不删除旧实现。
- 任何音频底层方案先做小型 spike，通过 fixture 后再进入正式页面。

## 9. 下一实施任务

第一批任务应严格限定为 M0：

1. Xcode 创建 macOS SwiftUI App 到 `OwlListenApp/`。
2. 初始化 `OwlListenKit/Package.swift` 和 test target。
3. 增加共享 fixture（小音频、M4B、ZIP、标签）。
4. 首先移植 `PackMetadata` 和 `computeDiff`，用旧实现结果做测试。
5. 原生首页接入三个模式占位入口。

完成以上内容后，再开始 M1 的 ZIP 导入与片段播放。
