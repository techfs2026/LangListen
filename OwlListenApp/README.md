# OwlListenApp

macOS 原生应用层。详细路线见
[`docs/apple-native-migration.md`](../docs/apple-native-migration.md)。

## 职责

- SwiftUI 页面、导航、窗口和应用生命周期
- AppKit bridge、键盘快捷键、拖放和系统菜单
- 文件选择、麦克风权限、Finder 等系统集成
- feature model 与依赖装配
- macOS UI tests、签名、公证和发布配置

## 不应放在这里

- 数据包解析与序列化
- Diff 算法
- 音频解码、播放内核、波形峰值计算
- Whisper 封装
- SQLite repository

这些能力属于 `OwlListenKit`。

## 初始化约定

在 M0 阶段使用 Xcode 创建 macOS SwiftUI App，工程放在本目录。不要手工维护一份
尚未由 Xcode 生成的 `.xcodeproj`。
