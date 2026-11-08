# Feature Brief: Google Play 多渠道隔离与合规改造

## 1. Background & Problem
- **目标**：将心迹（ThoughtEcho）上架 Google Play，并确保 100% 符合 Google Play 开发者政策与技术审核标准。
- **核心合规阻断点**：
  1. `REQUEST_INSTALL_PACKAGES` 与应用内通过 `ApkDownloadService` 直接下载/安装 APK，违反 Google Play《设备和网络滥用政策》（Device and Network Abuse）；
  2. `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`，Google Play 严禁常规笔记应用申请电池白名单；
  3. `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` / `READ_MEDIA_AUDIO` / `READ_EXTERNAL_STORAGE` 宽泛权限，Google Play 强制要求普通应用使用系统 Android Photo Picker，严禁申请宽泛媒体权限；
  4. 需支持打包 Android App Bundle (AAB)。
- **核心约束（非 Google Play 渠道不受影响）**：
  - 官网与 GitHub 发布的独立 APK 必须原封不动保留应用内更新、后台保活与全部原生能力。
  - 项目保持在单一公开仓库中（不建私有仓库），敏感凭证与签名文件（Keystore / Google Play API JSON）通过 GitHub Actions Secrets 隔离。

## 2. Proposed Architecture Solution
1. **Android Product Flavors + Manifest Merger**：
   - 在 `android/app/build.gradle` 定义渠道维度：`standard` (官网/GitHub 默认) vs `play` (Google Play)；
   - 在 `android/app/src/play/AndroidManifest.xml` 中使用 `tools:node="remove"` 物理剔除敏感权限：
     - `REQUEST_INSTALL_PACKAGES`
     - `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
     - `READ_MEDIA_IMAGES`、`READ_MEDIA_VIDEO`、`READ_MEDIA_AUDIO`、`READ_EXTERNAL_STORAGE`
2. **Dart 编译期宏与运行时适配**：
   - 注入编译参数 `--dart-define=DISTRIBUTION_CHANNEL=play`；
   - 抽象 `DistributionConfig`：
     - Play 渠道：检测更新改为跳转 Google Play 详情页（`market://details?id=com.shangjin.thoughtecho`）或调用 In-App Updates，设置中隐藏电池优化引导；
     - Standard 渠道：保留现有 `ApkDownloadService` 与完整引导流程。
3. **CI/CD 与凭证安全**：
   - GitHub Actions 在打包 Play 渠道时注入 Secrets 生成签名 AAB 并自动发布。

## 3. Next Step
- 运行 EGM 规范设计与 Goldfish 审查流程，生成完整的技术设计文档 (`design_draft.md`) 并指导后续工程落地。
