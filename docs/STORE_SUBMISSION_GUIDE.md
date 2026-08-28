# ThoughtEcho (心迹) - 双端应用商店上架填表与防拒保姆级手册

本手册汇总了在 **Google Play Console** 和 **Apple App Store Connect** 提审时所需填写的全部问卷答案、合规声明、文案及审核员备注模板。

---

## 🍎 一、Apple App Store Connect 提审指南

### 1. App 隐私问卷 (App Privacy Nutrition Label)
提审路径：`App Store Connect` -> `你的 App` -> `App 隐私` -> `开始使用`

* **是否从此 App 收集数据？**
  * 建议选择：**“否，我们不会从此 App 收集数据”**
  * *说明*：ThoughtEcho 采用本地优先（Local-First）架构，所有笔记、音频、图片均保存在用户本地 SQLite / 媒体目录中，无后台用户账号系统，Sentry 默认处于关闭状态。
* **如果启用了崩溃日志收集（可选声明）**：
  * 数据类型：`诊断 (Diagnostics)` -> `崩溃数据 (Crash Data)` / `性能数据 (Performance Data)`
  * 是否与用户身份关联：**否**
  * 是否用于追踪目的：**否**

### 2. 出口合规证明 (Export Compliance)
提审构建版本时，系统会弹出出口合规性对话框：
* **问题：您的 App 是否使用加密？**
  * 选择：**“是” (Yes)**
* **问题：您的 App 是否符合指定免除条款？**
  * 选择：**“是” (Yes)**
  * *说明*：Flutter 应用仅使用系统标准加密库（HTTPS/SSL、SQLite 标准加密、本地加解密），属于通用豁免范畴（Category 5, Part 2 Exemption），无需提供美国商务部 ERN 审批编号。

### 3. App 审核信息与备注 (App Review Information)
提审路径：`准备提交` -> `App 审核信息`

* **登录信息 (Sign-in information)**：
  * **勾选 “不需要登录” (Sign-in not required)**
* **审核备注 (Notes)**：直接复制以下模板填入备注框：
  ```text
  Hello Apple Review Team,

  Thank You for reviewing ThoughtEcho.

  1. Sign-in: ThoughtEcho is a local-first, privacy-focused thought journal and note-taking application. All notes and multimedia attachments are stored locally on the device's storage. No sign-in or account registration is required to access all core features.
  2. AI Features: All AI capabilities (such as text polishing and reflection assistants) either use public daily inspirational quote feeds (Hitokoto / ZenQuotes) or allow users to optionally configure their own personal API key (Bring-Your-Own-Key). There are no gated in-app purchases or third-party payment workarounds.
  3. Support & Privacy:
     - Privacy Policy: https://note.shangjinyun.cn/privacy.html
     - User Guide & Support: https://note.shangjinyun.cn/user-guide.html

  If you have any questions during the review process, please feel free to reach out. Thank you!
  ```

---

## 🤖 二、Google Play Console 提审指南

### 1. 数据安全表单 (Data Safety)
提审路径：`Google Play Console` -> `政策和计划` -> `应用内容` -> `数据安全`

| 数据类型 | 是否收集 | 是否与个人身份关联 | 用途说明 | 是否加密传输 | 是否允许删除 |
| :--- | :---: | :---: | :--- | :---: | :---: |
| **大致/精准位置 (Location)** | 是 | 否 | **应用功能**（用于在用户记笔记时自动附加地理位置标记，仅存本地） | 是 | 是 |
| **照片和视频 (Photos & Videos)** | 是 | 否 | **应用功能**（用于在笔记中插入图片、视频与实况照片附件） | 是 | 是 |
| **录音/音频文件 (Audio)** | 是 | 否 | **应用功能**（用于在笔记中录制或附加语音备忘） | 是 | 是 |
| **文件和文档 (Files & Docs)** | 是 | 否 | **应用功能**（用于笔记的备份导入与恢复导出） | 是 | 是 |

* **数据安全声明总结问题**：
  * 传输中加密？ **是**
  * 用户可以申请删除数据？ **是**（用户可随时在 App 内清除全部笔记与本地数据）
  * 是否为家庭/儿童应用？ **否**（遵循标准常规分级）

### 2. 目标受众与内容分级 (Target Audience & Content Rating)
* **年龄层**：选择 **13 岁及以上**（13-15、16-17、18 岁以上）。
* **IARC 内容分级问卷**：
  * 类别：**实用工具、效率、办公或备忘录 (Utility / Productivity)**
  * 是否含暴力、色情、脏话、赌博、违禁品？ **全部选“否”**
  * 是否共享用户位置给其他用户？ **否**
  * 是否允许用户之间在线交流？ **否**

### 3. 应用访问权限与声明 (App Access)
* **访问权限受限？**
  * 选择：**“所有功能均可直接使用，无需任何凭据”**。
* **广告？**
  * 选择：**“否，我的应用不包含广告”**。
* **前台服务 (Foreground Service)**：
  * 勾选 `Data Sync (数据同步)`，说明用于局域网笔记设备间同步与定时提醒调度。

---

## 📝 三、应用商店文案速查 (Store Listing Quick Reference)

### 🇨🇳 简体中文
* **应用标题**: 心迹 - 灵感摘录与思考笔记
* **副标题 / 短标题**: 想到就记，读到就摘，剩下的交给 AI
* **简短描述 (80字以内)**:
  ```text
  想到就记，读到就摘。本地优先的灵感与思考笔记，支持纸墨排版、离线记录、Thoughter AI 伴侣与私密同步。
  ```

### 🇺🇸 English
* **Title**: ThoughtEcho - Inspiration & Thought Journal
* **Subtitle / Short Title**: Jot it down, clip what you read
* **Short Description (under 80 words)**:
  ```text
  Jot it down, clip what you read. A local-first inspiration journal with artisan typography, offline capture, Thoughter AI companion & private sync.
  ```

---

## 🔗 四、关键公开 URL（随时可供商店审查）

* **隐私政策 (Privacy Policy)**: `https://note.shangjinyun.cn/privacy.html`
* **用户指南与技术支持 (Support URL)**: `https://note.shangjinyun.cn/user-guide.html`
* **官方网站 (Official Website)**: `https://note.shangjinyun.cn/`
