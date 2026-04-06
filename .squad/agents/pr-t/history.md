# PR-T 的项目记忆

## 核心背景

- 项目: ThoughtEcho (心迹)
- 负责人: 上晋
- 我的角色: 商店运营
- Microsoft Store ID: 9NC7GDG6KFMC

## Learnings

<!-- 在此追加学到的项目知识 -->

### 2025-06-28: 商店上架状态检查

**Microsoft Store 上架情况:**
- Store ID: 9NC7GDG6KFMC
- 当前状态: ✅ 已上架，可正常访问
- Store 页面标题: "ThoughtEcho - Free download and install on Windows"
- 应用描述: 完整详细，涵盖所有核心功能（富文本、AI、备份、隐私等）
- Publisher: Shangjinyun

**版本信息:**
- pubspec.yaml 版本: 3.4.0+1
- MSIX 版本: 3.4.0.0 (符合 MS Store 第四位为 0 的要求)
- Identity Name: Shangjinyun.330094822087A

**商店资产完整度:**
- README 截图: 13 张（涵盖主要功能页面）
- Windows Tiles: 完整（44x44, 71x71, 150x150, 310x310, Wide310x150 含多尺度）
- 应用图标: ICO + PNG 完整配置
- 商店描述: 英文详尽，功能分类清晰

**CI/CD 发布流程:**
- Windows: `build-windows.yml` (手动触发，支持版本号输入，MSIX 签名配置 = false 由 Store 自动签名)
- Android: `flutter-release-build.yml` (手动触发，支持 32/64 位)
- iOS: `ios-build.yml` (待确认无签名构建)

**待改进项:**
- Google Play / App Store 链接尚未在 README 中添加
- 中文商店描述可能需要本地化提交
- 商店截图可考虑更新为最新 UI 版本
