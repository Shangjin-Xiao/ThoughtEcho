<div align="center">
  <a href="https://note.shangjinyun.cn/">
    <img src="https://img.shangjinyun.cn/projects/thoughtecho/readme-banner.png" alt="ThoughtEcho 心跡 - 你的專屬靈感摘錄筆記本" width="100%">
  </a>
  
  # 心跡 (ThoughtEcho)
  
  <p align="center">
    <b>📝 你的專屬 AI 靈感摘錄筆記本 · 想到就記，讀到就摘，剩下的交給 AI。</b><br>
    <b>Your Personal AI-Powered Inspiration Notebook — Jot it down, clip what you read, let AI sort out the rest.</b>
  </p>

  <p align="center">
    <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/releases/latest">
      <img src="https://img.shields.io/github/v/release/Shangjin-Xiao/ThoughtEcho?style=flat-square&color=3cb371" alt="最新版本">
    </a>
    <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/releases">
      <img src="https://img.shields.io/github/downloads/Shangjin-Xiao/ThoughtEcho/total?style=flat-square&color=0078D7" alt="總下載量">
    </a>
    <a href="https://www.microsoft.com/store/apps/9NC7GDG6KFMC">
      <img src="https://img.shields.io/badge/Microsoft_Store-0078D7?style=flat-square&logo=windows&logoColor=white" alt="Microsoft Store">
    </a>
    <a href="https://flutter.dev/">
      <img src="https://img.shields.io/badge/Flutter-3.29+-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter 3.29+">
    </a>
    <a href="https://github.com/Shangjin-Xiao/ThoughtEcho">
      <img src="https://img.shields.io/badge/Platform-Windows%20%7C%20Android%20%7C%20iOS-informational?style=flat-square" alt="支援平台: Windows | Android | iOS">
    </a>
    <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/stargazers">
      <img src="https://img.shields.io/github/stars/Shangjin-Xiao/ThoughtEcho?style=flat-square&color=FFD700" alt="GitHub Stars">
    </a>
    <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/blob/main/LICENSE">
      <img src="https://img.shields.io/github/license/Shangjin-Xiao/ThoughtEcho?style=flat-square" alt="授權條款: MIT">
    </a>
  </p>

  <p align="center">
    <a href="README.md"><b>English</b></a> • 
    <a href="README_CN.md"><b>简体中文</b></a> •
    <a href="README.zh-Hant.md"><b>繁體中文</b></a> •
    <a href="README_JA.md"><b>日本語</b></a> •
    <a href="README_KO.md"><b>한국어</b></a> •
    <a href="https://note.shangjinyun.cn/"><b>官方網站</b></a> •
    <a href="docs/USER_MANUAL.md"><b>使用者手冊</b></a> •
    <a href="https://shangjin-xiao.github.io/ThoughtEcho/user-guide.html"><b>網頁指南</b></a>
  </p>

  <h3>📥 下載管道 / Download</h3>
  <p align="center">
    <a href="https://www.microsoft.com/store/apps/9NC7GDG6KFMC"><img src="https://get.microsoft.com/images/zh-tw%20dark.svg" width="160" alt="從 Microsoft Store 取得"></a>
    &nbsp;&nbsp;&nbsp;
    <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/releases/latest"><img src="https://img.shields.io/badge/Android_APK-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android APK"></a>
  </p>

  <p><sub>Windows：推薦由 Microsoft Store 安裝（支援自動更新）· Android：請至 <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/releases/latest">GitHub Releases</a> 下載 APK</sub></p>
  <p><sub>🌍 <b>語言支援：</b>完整支援 <b>繁體中文</b>、<b>简体中文</b>、<b>English</b>、<b>日本語</b> 與 <b>한국어</b>（德語、西班牙語、法語等正在完善中）</sub></p>
  
</div>

---

> **ThoughtEcho（心跡）** 是一款優雅、本機優先、AI 賦能的跨平台靈感筆記與知識摘錄應用程式。  
> **ThoughtEcho** is an elegant, local-first, AI-powered cross-platform inspiration and quote notebook designed to capture fleeting thoughts, organize reading excerpts, and unlock deeper creative potential.

---

## 🌟 為什麼選擇 ThoughtEcho？

- 🔒 **本機優先與隱私保障 (Local-First & Privacy)**：100% 資料自主掌控，採用 SQLite 與 MMKV 於本機安全儲存。敏感筆記支援隱藏標籤並可透過生物辨識（指紋 / 臉部辨識 Face ID）防護解鎖。無任何追蹤行為，絕無強制雲端綁定。
- 💡 **Thoughter 智慧代理與長期記憶 (Thoughter AI Agent & Long-Term Memory)**：多服務商 AI 架構（支援 OpenAI、DeepSeek、Ollama、Gemini、Claude、OpenRouter、SiliconFlow 等）。內建具備跨對話長期記憶庫的自主 Thoughter Agent，深度理解你的寫作風格與思考習慣。
- ✍️ **豐富多媒體與情境感知 (Rich Multimedia & Context Capture)**：Quill 富文本排版，支援圖片、音訊與影片附件。自動感知並記錄地理逆編碼位置、即時天氣與不同時段的靈感當下情境。
- 📊 **週期洞察與精美卡片 (Periodic Insights & Card Generation)**：自動生成每週與每月深度反思洞察、年度回顧報告、思考脈絡與寫作趨勢分析，並支援一鍵生成 AI 名言精美分享卡片。
- 🔄 **零設定多裝置同步 (Zero-Config Multi-Device Sync)**：LocalSend 高速區域網路直接同步（mDNS 裝置自動探索與加密傳輸），搭配彈性的 WebDAV 雲端備份與還原機制。
- 🎨 **手作美學主題與專屬排版 (Artistic Themes & Typography)**：獨家手作「紙與墨」及「素箋」風格，搭配專為閱讀調校的字體排印設計，另支援 Material 3 動態取色色盤。

<br>

## ✨ 功能特色

<div align="center">
  <table>
    <tr>
      <td align="center" width="33%"><b>✍️ 富文本筆記</b><br>Quill 富文本排版、多媒體附件（圖片/音訊/影片），純文字與富文本雙重儲存</td>
      <td align="center" width="33%"><b>✨ Thoughter 智慧代理</b><br>Agent 工具調用、專屬長期記憶資料庫、互動式創作靈感助手</td>
      <td align="center" width="33%"><b>📊 洞察與報告</b><br>AI 週期性深度洞察、年度回顧報告、創作節奏與寫作趨勢分析</td>
    </tr>
    <tr>
      <td align="center"><b>🏷️ 標籤與搜尋</b><br>多標籤篩選、智慧排序、極速本機 SQLite 全文檢索</td>
      <td align="center"><b>🎯 AI 卡片生成</b><br>將筆記轉化為優美、可自訂樣式的藝術分享卡片</td>
      <td align="center"><b>📦 媒體與備份中心</b><br>大檔串流分段處理、完整 ZIP 匯入/匯出、增量同步機制</td>
    </tr>
    <tr>
      <td align="center"><b>🌍 情境感知記錄</b><br>自動記錄地理位置、即時天氣與時間段等靈感上下文</td>
      <td align="center"><b>🙈 隱私安全防護</b><br>隱藏筆記標籤 + 系統生物辨識（指紋 / 臉部辨識 Face ID / Windows Hello）解鎖</td>
      <td align="center"><b>💾 草稿自動儲存</b><br>編輯時即時自動暫存，遇閃退崩潰即刻還原，絕不遺失任何靈感</td>
    </tr>
    <tr>
      <td align="center"><b>⚡ 快速捕捉</b><br>智慧剪貼簿監聽、每日一言（Hitokoto / ZenQuotes 等）、AI 靈感寫作引導</td>
      <td align="center"><b>🎨 精品手作主題</b><br>紙與墨、素箋與 Material 3 動態色彩語彙</td>
      <td align="center"><b>🔄 多裝置資料同步</b><br>LocalSend 區域網路高速直接傳輸 + WebDAV 雲端備份與還原</td>
    </tr>
  </table>
</div>

## 📸 應用程式截圖

### 核心功能
| 首頁 | 筆記列表 |
|:---:|:---:|
| ![首頁](https://img.shangjinyun.cn/projects/thoughtecho/home_page.jpg) | ![筆記列表](https://img.shangjinyun.cn/projects/thoughtecho/note_list_view.jpg) |

### 編輯與 AI 功能
| 富文本編輯器 | AI 問答對話 |
|:---:|:---:|
| ![富文本編輯器](https://img.shangjinyun.cn/projects/thoughtecho/note_full_editor_page.jpg) | ![AI 問答對話](https://img.shangjinyun.cn/projects/thoughtecho/note_qa_chat_page.jpg) |

### 洞察與報告
| 洞察分析 | 週期報告 |
|:---:|:---:|
| ![洞察分析](https://img.shangjinyun.cn/projects/thoughtecho/insights_page.jpg) | ![週期報告](https://img.shangjinyun.cn/projects/thoughtecho/period_report.jpg) |

### 設定與管理
| 主題風格設定 | AI 服務商設定 | 每日一言設定 |
|:---:|:---:|:---:|
| ![主題風格設定](https://img.shangjinyun.cn/projects/thoughtecho/theme_settings_page.jpg) | ![AI 服務商設定](https://img.shangjinyun.cn/projects/thoughtecho/l10n/en/ai_settings_page.jpg) | ![每日一言設定](https://img.shangjinyun.cn/projects/thoughtecho/hitokoto_settings_page.jpg) |

| 偏好設定 | 智慧推播設定 |
|:---:|:---:|
| ![偏好設定](https://img.shangjinyun.cn/projects/thoughtecho/preferences_detail_page.jpg) | ![智慧推播設定](https://img.shangjinyun.cn/projects/thoughtecho/smart_push_settings_page.jpg) |

### 儲存與備份
| WebDAV 雲端同步 | 資源回收筒 |
|:---:|:---:|
| ![WebDAV 雲端同步](https://img.shangjinyun.cn/projects/thoughtecho/webdav_sync_page.jpg) | ![資源回收筒](https://img.shangjinyun.cn/projects/thoughtecho/recycle_bin_page.jpg) |

## 🛠️ 技術棧

<div align="center">
  <table>
    <tr>
      <td align="center"><b>應用程式框架</b></td>
      <td>Flutter (Dart) - 現代響應式跨平台框架</td>
    </tr>
    <tr>
      <td align="center"><b>狀態管理</b></td>
      <td>Provider, GetIt - 響應式狀態編排與相依性注入</td>
    </tr>
    <tr>
      <td align="center"><b>本機資料庫</b></td>
      <td>sqflite（行動端）與 sqflite_common_ffi（桌面端 SQLite FFI）</td>
    </tr>
    <tr>
      <td align="center"><b>富文本引擎</b></td>
      <td>flutter_quill - 支援圖片、音訊與影片嵌入的精美排版引擎</td>
    </tr>
    <tr>
      <td align="center"><b>AI 服務架構</b></td>
      <td>OpenAI 相容通訊協定架構（內建預設：Ollama、OpenAI、DeepSeek、Gemini、Claude、OpenRouter、SiliconFlow 等服務商）</td>
    </tr>
    <tr>
      <td align="center"><b>儲存與安全</b></td>
      <td>MMKV（高效能鍵值快取）+ flutter_secure_storage（金鑰安全加密儲存）</td>
    </tr>
    <tr>
      <td align="center"><b>多裝置同步</b></td>
      <td>LocalSend（區域網路 mDNS 自動探索與 TLS 加密傳輸）+ WebDAV 雲端同步</td>
    </tr>
    <tr>
      <td align="center"><b>媒體處理</b></td>
      <td>大檔串流分段處理、智慧快取與無損壓縮</td>
    </tr>
    <tr>
      <td align="center"><b>支援平台</b></td>
      <td>Windows、Android、iOS（注：不支援 Web 平台）</td>
    </tr>
  </table>
</div>

## 🚀 快速開始

1. **環境準備**
   
   確保已安裝 Flutter 3.29+ 與 Dart 3.5+ 環境。執行 `flutter doctor` 檢查環境配置：
   ```bash
   flutter doctor
   ```

2. **複製專案原始碼**
   ```bash
   git clone https://github.com/Shangjin-Xiao/ThoughtEcho.git
   cd ThoughtEcho
   ```

3. **安裝相依套件**
   ```bash
   flutter pub get
   ```

4. **執行應用程式**
   ```bash
   flutter run
   ```

5. **設定 AI 服務（選用）**
   
   在應用程式內前往「**設定 → AI 設定**」，選擇預設的 AI 服務商（如 DeepSeek、Ollama、OpenAI 等），填入你的 API Key，即可啟用 AI 問答、Thoughter 智慧代理與週期洞察等功能。

## 🗺️ 發展藍圖

<div align="center">
  <table>
    <tr>
      <th>已完成 ✅</th>
      <th>長期規劃 💡</th>
    </tr>
    <tr>
      <td>
        • 支援多媒體（圖片、音訊、影片）的富文本編輯器<br>
        • 相容 OpenAI 通訊協定的多 AI 服務商架構<br>
        • 具備專屬長期記憶庫的 Thoughter AI 智慧代理<br>
        • 紙與墨 / 素箋 / Material 3 獨家特色主題樣式<br>
        • 支援自訂分享模板的 AI 名言卡片生成<br>
        • 大檔安全串流處理與 ZIP 完整備份/還原<br>
        • LocalSend 區域網路高速直接傳輸與 WebDAV 雲端同步<br>
        • 智慧地理逆編碼搜尋與自動天氣記錄<br>
        • 智慧剪貼簿監聽與啟動即刻快速捕捉<br>
        • 週期性智慧洞察報告與年度回顧<br>
        • 支援生物辨識（指紋 / 臉部辨識 Face ID）防護的隱藏筆記<br>
        • 編輯草稿即時自動儲存與閃退崩潰還原<br>
        • 多語言國際化支援（完整支援英文/繁中/簡中/日文/韓文；預設回退至英文）<br>
        • Windows 桌面端應用程式（MSIX 安裝套件）<br>
        • iOS 平台支援與持續整合（CI）建置流程<br>
        • 應用程式內建更新說明頁（Release Notes）與主題即時預覽
      </td>
      <td>
        <b>🔥 智慧輸入升級</b><br>
        • AI 自然語言語意搜尋<br>
        • 語音轉文字隨想速記<br>
        • 相機拍照 OCR 文字辨識<br>
        • AI 自動擷取作者與出處來源<br><br>
        <b>🌍 使用者體驗與知識庫</b><br>
        • 互動式筆記本主題與自訂紙張質感<br>
        • 知識圖譜關聯與主題分群<br>
        • 地圖選點與記憶足跡可視化<br><br>
        <b>✨ 裝置端 AI 能力探索</b><br>
        • 裝置端輕量化離線大型語言模型推理<br>
        • 本機離線 OCR 辨識與離線語音轉寫<br>
        • 更多第三方筆記軟體匯入/匯出格式適配
      </td>
    </tr>
  </table>
</div>

> 📝 深入技術文件請參閱 [專案概覽](docs/project-overview.md) 與 [使用者手冊](docs/USER_MANUAL.md)。

## 🤝 如何貢獻

我們非常歡迎各種形式的社群貢獻！你可以透過以下方式參與：

1. **回報問題或提出建議**：在 [GitHub Issues](https://github.com/Shangjin-Xiao/ThoughtEcho/issues) 開立 Issue 回報 Bug 或分享新功能想法
2. **協助在地化翻譯 🌍**：
   - 協助完善德語、西班牙語、法語等語系的詞條翻譯
   - 審閱並精進現有翻譯品質（繁體中文、簡體中文、英文、日文、韓文）
3. **貢獻程式碼**：
   - Fork 本專案並建立功能分支 `feature/YourFeature` 或 `fix/YourBugFix`
   - 確保你的程式碼通過靜態分析與測試
   - 提交 Pull Request 並清楚描述所做的變更
4. **推廣與支援**：給專案點亮一顆 ⭐ Star，並將 ThoughtEcho 分享給身邊的朋友！

## 📄 授權條款

本專案基於 [MIT 授權條款](LICENSE) 開源 — 歡迎自由使用、修改與分發。

## 🙏 致謝

感謝以下開源專案與服務提供商的大力支援：
- [Flutter](https://flutter.dev/) - 跨平台 UI 框架
- [LocalSend](https://github.com/localsend/localsend) - 區域網路同步通訊協定
- [Sentry](https://sentry.io/) - 應用程式閃退與結構化記錄監控
- [一言（Hitokoto）](https://hitokoto.cn/) - 中文每日名言服務商
- [ZenQuotes](https://zenquotes.io/) - 英文每日名言服務商
- [API Ninjas Quotes API](https://api-ninjas.com/api/quotes) - 分類名言服務商
- [名言教えるよ (Meigen Oshieruyo)](https://meigen.doodlenote.net/) - 日文每日名言服務商
- [Korean Advice](https://korean-advice-open-api.vercel.app/) - 韓文每日名言服務商
- [Open-Meteo](https://open-meteo.com/) - 天氣資料服務
- [OpenStreetMap Nominatim](https://nominatim.openstreetmap.org/) - 地理編碼與反查服務
