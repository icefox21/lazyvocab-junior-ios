# 懒得记单词 - iOS 初中中考专项版 (Turnkey iOS Project)

本工程为《懒得记单词》专为 iOS 平台优化的初中独立发布版本。已在 Windows 端完成全部原生底层适配、代码校验与离线资源全量封装，可在任意 Mac 或 CI/CD 云端环境中 1 键编译运行与打包签名。

---

## 📱 核心功能与技术指标

1. **词库范围**：
   - **初中中考大纲词库 100% 独占收录**（1,877 核心大纲词汇）。
   - 内置 **15,026 组** 纯正美式/英式/专业中文释义与语源切片（~235MB 原生音频）。
   - **完全脱机离线**：安装即用，0 网络依赖，0 流量消耗。

2. **iOS 原生音频与硬件适配**：
   - **静音物理按键穿透**：底层已配置 `AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])`，iPhone 拨到侧边静音红点也能正常出声，彻底解决 iOS Safari / WKWebView 常见静音 BUG。
   - **后台持续朗读**：`Info.plist` 已配置 `UIBackgroundModes -> audio`，息屏时保持定时循环磨耳朵。
   - **原生双语 TTS 兜底**：`ios/Runner/AppDelegate.swift` 实现了 `AVSpeechSynthesizer` 与 Flutter `MethodChannel('lazyvocab/tts')` 的无缝双向桥接，任意生僻内容皆可纯正发音。
   - **WKWebView 自动播放许可**：已配置 `allowsInlineMediaPlayback = true` 与 `mediaTypesRequiringUserAction = {}`，页面加载后可顺畅自动推进学习流程。

---

## 🛠️ 在 Mac 上的 1 键编译与运行步骤

### 运行环境要求
- **macOS**：macOS 13+ (Ventura / Sonoma / Sequoia)
- **Xcode**：Xcode 14+ (需安装 Command Line Tools)
- **Flutter SDK**：3.24.5 或更高版本
- **CocoaPods**：1.12+ (`sudo gem install cocoapods` 或 `brew install cocoapods`)

### 构建命令
在终端打开本项目根目录：

```bash
# 1. 获取依赖包
flutter pub get

# 2. 安装 iOS 原生 Pod 依赖
cd ios
pod install
cd ..

# 3. 运行到真机或模拟器 (插上 iPhone 并开启开发者模式)
flutter run -d ios

# 4. 打包未签名 IPA (供 AltStore / 巨魔 TrollStore / 个人签名安装)
flutter build ipa --no-codesign

# 5. 或在 Xcode 中打开工程进行正式签名上架发布
open ios/Runner.xcworkspace
```

> **提示**：在 Xcode 中打开 `Runner.xcworkspace`，在 `Runner -> Signing & Capabilities` 选择你的 Apple 开发者账号 Team，点击 Xcode 顶部的 **Product -> Archive** 即可直接导出 App Store 发布包或 Ad-Hoc 内部测试包。

---

## ☁️ 免 Mac 云端构建方案 (GitHub Actions)

如果你手头暂时没有 Mac 电脑，仓库内已提供 `.github/workflows/build_ios.yml`：
1. 将本项目推送到你的 GitHub 私有仓库；
2. 进入仓库的 **Actions** 标签页，触发 **Build iOS IPA** 工作流；
3. 构建完成后，在 **Artifacts** 中即可直接下载编译生成的无签名 `.ipa` 安装包，可使用爱思助手、AltStore 或 Sideloadly 直接装入 iPhone。
