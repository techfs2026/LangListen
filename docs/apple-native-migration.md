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
| 峰值计算 | AVAudioFile + Accelerate，分块并发生成多分辨率峰值 |
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

### M1：初次精听可用版本

这是当前最高优先级。先迁移能满足日常使用的闭环，不等待完整的长音频性能方案。

#### M1.1：播放与标注 MVP

状态：**原生实现已完成，等待实际使用验收。**

迁移顺序：

1. 长音频文件选择、打开与元数据读取。
2. 播放、暂停、seek、播放头和基础时间轴。
3. 生成并显示基础波形。
4. 拖拽框选片段、边界调整、选中自动 AB 循环。
5. 标签新增、编辑、删除。
6. 标签文件导入、导出和核心快捷键。

验收：

- 可以打开实际使用的音频并连续播放。
- 可以在波形上框选难句并自动循环。
- 重启前可导出标签，重新打开后可恢复标注。
- 播放、框选和标签编辑不阻塞 UI。

当前实现包括：

- Home 页面作为功能入口，M1 是独立的初次精听页面。
- AVPlayer 播放、暂停、seek、0.5x-1.5x 变速。
- 分块读取音频并生成固定数量峰值，不在结果中保留完整 PCM。
- 可视时间窗口、缩放、左右移动、时间刻度和播放头跟随。
- 波形点击定位、拖拽框选、边缘调整和选区自动循环。
- 标签卡片编辑、删除、Audacity 文本格式导入/导出。
- 空格播放、`L` 切换循环、`←/→` 切换片段、`Command-O` 打开音频。

M1.1 使用固定约 4000 个全局峰值。它足够验证流程，但高倍率放大和数小时音频的
细节与加载性能仍属于 M1.2。

MVP 可以先对中短音频使用内存峰值，但接口必须允许后续替换，不能让 UI 直接持有
完整 PCM。

#### M1.2：长音频与波形性能

状态：**原生实现已完成，等待真实长音频性能验收。**

1. 后台生成多分辨率峰值。
2. 按可视范围查询多分辨率峰值。
3. 优化缩放、滚动、播放头同步和窗口缩放。
4. 测试数小时音频的内存、首次加载速度。

当前实现包括：

- `OwlListenKit` 分块读取音频并生成多分辨率峰值金字塔，不保留完整 PCM。
- 波形视图只查询当前时间窗口所需的层级和点数。
- 峰值生成使用 Accelerate 向量计算，并在读取块内并发处理多个峰值区间。
- 窗口尺寸变化会按实际像素密度重新查询，缩放和平移不再依赖固定 4000 个全局峰值。
- 初次精听页面按旧 `AnnotateScreen` 代码结构重建，未使用旧 UI 截图作为实现依据。
- 保留波形拖拽框选和边界调整；捏合缩放，按住 Shift 拖拽平移。

验收：

- 数小时音频不长期保留完整 PCM。
- 缩放和拖动流畅，播放头与可闻位置保持可接受误差。

#### M1.3：切割、Whisper 与数据包导出

迁移顺序：

1. 按标签边界切割为 16kHz 单声道片段。
2. 集成 whisper.cpp，封装模型加载、缓存、取消和进度。
3. 生成 metadata 与片段目录。
4. 构建 ZIP，并支持 Finder 定位。
5. 录音、麦克风权限、录音转写。

当前实现：

- 初次精听页已接入旧版同结构的导出面板，支持进度、取消、错误恢复和 Finder 定位。
- FFmpeg 最多并发切割 4 个片段，输出与旧版一致的 16kHz 单声道
  `segments/0000.mp3`。
- `OwlListenKit` 通过 C 桥接直接调用 vendored whisper.cpp 1.8.3，使用 CPU +
  Accelerate 后端；`small.en` 模型在 Swift actor 中缓存，不启动额外 CLI 进程。
- 继续复用 `ggml-small.en.bin`，模型文件由 `.gitignore` 排除。
- ZIP 根目录、`metadata.json` 版本和 `text`/`label` 字段与旧 Tauri 实现保持一致。
- `OwlListenKit` 提供麦克风授权、录音、取消录音和录音转写能力；初次精听页不新增
  旧 `AnnotateScreen` 中不存在的录音按钮，后续由复习页复用。

开发环境可以继续使用 `src-tauri/whisper-models/ggml-small.en.bin`。发布包需要把
`ffmpeg` 和 `whisper-models/ggml-small.en.bin` 放入 App Resources；模型下载与
更新策略仍作为发布流程单独处理。

验收：

- 导出的 ZIP 可以被旧 Tauri 版本导入。
- 切割起止点、命名、排序与 metadata 一致。
- 转写任务不会阻塞 UI，可取消，错误可恢复。
- Whisper 模型不被打进 Git；发布方式和首次下载策略单独确定。

完成 M1.1 后，原生版已经可以承担日常初次精听；M1.2 与 M1.3 在此基础上补齐
性能和完整导出能力。

### M2：精听复习

迁移顺序：

1. `PackMetadata`、`ListenSegment`、状态模型。
2. ZIP 导入、metadata 校验、片段读取。
3. 短音频播放、暂停、重播、循环。
4. 听写输入、词级 Diff、正确率。
5. done/flagged 状态、片段导航和快捷键。
6. 录音输入与 Whisper 转写复用 M1 的转写能力。

暂不包含：历史记录、跨数据包统计。

验收：

- 同一 ZIP 在 Tauri 和原生版显示相同片段顺序与文本。
- 固定 Diff fixture 的操作序列和准确率完全一致。
- 键盘可以完成完整复习流程。

### M3：有声书

有声书与精听数据链路相对独立，最后迁移。

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

### M4：0.1.x 功能等价与切换

- 建立逐项 parity checklist。
- 对三个工作流执行回归测试和性能测试。
- 完成沙盒、签名、公证、权限描述和发布构建。
- 原生版本连续使用一个稳定周期后，再决定是否归档 Tauri 代码。

退出条件：

- 没有阻断日常使用的数据兼容问题。
- 旧数据包可以读取，新数据包可回退读取。
- 崩溃、播放、seek、休眠/唤醒、音频设备切换经过测试。

### M5：实施 0.2.0 训练系统

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

M1.1 与 M1.2 代码已经完成。下一批任务：

1. 使用真实的短音频、课程音频和数小时长音频手工验收 M1.1/M1.2。
2. 修复实际使用中发现的交互与格式兼容问题。
3. 记录首次生成、缩放滚动和内存占用，再进入 M1.3。

精听复习和有声书继续只保留 Home 入口占位，不在 M1 阶段同时开发。
