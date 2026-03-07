---
name: material-design
version: 1.0.0
description: Google Material Design 3 实战参考。涵盖 Material You 动态色彩、排版系统、组件规格、Shape 系统、Motion 规范、Dark Theme 适配和 Jetpack Compose/Flutter 对照。适用于 Android 应用、Web 应用和跨平台应用的 UI 设计决策。
---

# Google Material Design 3 实战参考

Material Design 3（Material You）的实战速查，覆盖色彩、排版、组件和动效。

## 适用场景

- Android 应用 UI 设计（Jetpack Compose / XML Views）
- Flutter 跨平台应用
- Web 应用使用 Material 组件库（MUI / Angular Material）
- 审计现有 UI 是否符合 Material 3 规范

## 不适用

- macOS / iOS 原生应用（参考 apple-hig）
- Windows 原生应用（参考 fluent-design）

---

## 1. 核心设计原则

Material 3 的三大支柱：

| 原则 | 含义 | 实践 |
|------|------|------|
| **Personal（个性化）** | 适应用户偏好 | Dynamic Color 从壁纸取色 |
| **Adaptive（自适应）** | 适应各种设备 | 响应式布局、折叠屏支持 |
| **Expressive（表达力）** | 丰富的视觉表达 | 大圆角、色彩层次、motion |

### 与 Apple HIG / Fluent 的区别

```
Apple:   做减法，克制，内容优先
Fluent:  融入环境（Mica/Acrylic），层次丰富
Material: 做加法，表达力强，色彩大胆，圆角更大
```

---

## 2. 色彩系统（Dynamic Color）

### Material 3 色彩方案

M3 使用 **色调调色板（Tonal Palette）** 生成完整配色：

```
Source Color（种子色）
  → Primary Palette（主色调 13 级）
  → Secondary Palette（辅色调 13 级）
  → Tertiary Palette（第三色调 13 级）
  → Neutral Palette（中性色 13 级）
  → Neutral Variant Palette（中性变体 13 级）
  → Error Palette（错误色 13 级）
```

### 关键色槽（Key Color Roles）

| 角色 | Light | Dark | 用途 |
|------|-------|------|------|
| Primary | Tone 40 | Tone 80 | 主要交互元素（FAB、按钮） |
| On Primary | Tone 100 | Tone 20 | Primary 上的文字/图标 |
| Primary Container | Tone 90 | Tone 30 | 次要强调容器 |
| On Primary Container | Tone 10 | Tone 90 | 容器上的内容 |
| Secondary | Tone 40 | Tone 80 | 次要交互元素 |
| Tertiary | Tone 40 | Tone 80 | 对比/强调 |
| Surface | Tone 99 | Tone 6 | 页面主背景 |
| Surface Variant | Tone 90 | Tone 30 | 卡片/区块背景 |
| On Surface | Tone 10 | Tone 90 | 主文字 |
| On Surface Variant | Tone 30 | Tone 80 | 辅助文字 |
| Outline | Tone 50 | Tone 60 | 边框 |
| Outline Variant | Tone 80 | Tone 30 | 弱边框/分隔线 |
| Error | `#B3261E` | `#F2B8B5` | 错误状态 |
| Background | Tone 99 | Tone 6 | 窗口背景 |

### Dynamic Color（Material You）

Android 12+ 支持从壁纸自动提取 Source Color：

```kotlin
// Jetpack Compose
val colorScheme = if (dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
    dynamicLightColorScheme(context) // 或 dynamicDarkColorScheme
} else {
    lightColorScheme(primary = Purple40, ...)
}
```

### 手动生成配色

使用 Google 官方工具：
- **Material Theme Builder**: https://m3.material.io/theme-builder
- 输入一个 Source Color → 自动生成完整 Light/Dark 方案
- 导出为 Compose / CSS / Figma Token

---

## 3. 排版

### 字体栈

```
Android: Roboto（系统默认）
Web:     'Roboto', system-ui, sans-serif
iOS:     SF Pro（Flutter 自动适配）
```

### Type Scale

| 角色 | 字号 | 字重 | 行高 | 间距 | 用途 |
|------|------|------|------|------|------|
| Display Large | 57px | Regular | 64px | -0.25px | 极大数字/英雄标题 |
| Display Medium | 45px | Regular | 52px | 0 | 大标题 |
| Display Small | 36px | Regular | 44px | 0 | 次大标题 |
| Headline Large | 32px | Regular | 40px | 0 | 页面标题 |
| Headline Medium | 28px | Regular | 36px | 0 | 区块标题 |
| Headline Small | 24px | Regular | 32px | 0 | 卡片标题 |
| Title Large | 22px | Regular | 28px | 0 | Top App Bar 标题 |
| Title Medium | 16px | Medium | 24px | 0.15px | Tab / Navigation 标签 |
| Title Small | 14px | Medium | 20px | 0.1px | 小标题 |
| Body Large | 16px | Regular | 24px | 0.5px | 默认正文 |
| Body Medium | 14px | Regular | 20px | 0.25px | 次要正文 |
| Body Small | 12px | Regular | 16px | 0.4px | 辅助文字 |
| Label Large | 14px | Medium | 20px | 0.1px | 按钮文字 |
| Label Medium | 12px | Medium | 16px | 0.5px | Badge |
| Label Small | 11px | Medium | 16px | 0.5px | 时间戳 |

### 与其他平台对比

```
Material Body Large = 16px → Apple Body = 13px (macOS) / 17px (iOS)
Material 偏大偏宽松，Apple 偏紧凑
Material 大量用 Medium 字重，Apple 偏 Regular
```

---

## 4. 组件规格

### 按钮

| 类型 | 高度 | 圆角 | 用途 |
|------|------|------|------|
| Filled | 40px | 20px（全圆角）| 主要操作 |
| Outlined | 40px | 20px | 次要操作 |
| Text | 40px | 20px | 低优先级操作 |
| Tonal | 40px | 20px | 介于 Filled 和 Outlined 之间 |
| FAB (Mini) | 40px | 12px | 次要浮动操作 |
| FAB | 56px | 16px | 主要浮动操作 |
| Extended FAB | 56px | 16px | 带文字的 FAB |
| Icon Button | 40×40px | 20px | 图标操作 |

### 输入

| 控件 | 高度 | 圆角 | 特征 |
|------|------|------|------|
| Text Field (Filled) | 56px | 顶部 4px | 底部下划线 |
| Text Field (Outlined) | 56px | 4px | 四周边框 |
| Checkbox | 18×18px | 2px | — |
| Radio | 20×20px | 50% | — |
| Switch | 32×52px | 16px | 大尺寸拨动 |
| Slider | 4px 轨道 | 2px | 圆形 thumb 20px |

### 容器

| 组件 | 圆角 | 阴影 |
|------|------|------|
| Card (Filled) | 12px | 无（底色区分）|
| Card (Elevated) | 12px | elevation 1 |
| Card (Outlined) | 12px | 无（边框区分）|
| Dialog | 28px | elevation 3 |
| Bottom Sheet | 28px (顶部) | elevation 1 |
| Chip | 8px | — |
| Navigation Bar | 0 | elevation 2 |

### 触控目标

```
最小触控目标：48×48dp
推荐触控目标：56×56dp（FAB）
间距：至少 8dp
```

---

## 5. Shape 系统

M3 的圆角规则（使用 dp）：

| Shape 级别 | 圆角值 | 适用组件 |
|-----------|--------|---------|
| None | 0dp | — |
| Extra Small | 4dp | Text Field, Menu |
| Small | 8dp | Chip, Snackbar |
| Medium | 12dp | Card, Search Bar |
| Large | 16dp | FAB, Navigation Drawer |
| Extra Large | 28dp | Dialog, Bottom Sheet |
| Full | 50%（圆形）| FAB Mini, Icon Button |

### 与其他平台对比

```
Material: 大圆角风格（Dialog 28dp, Button 20dp）
Apple:    中等圆角（Dialog ~12px, Button 5-7px）
Fluent:   小圆角（Dialog 8px, Button 4px）
```

Material 3 的圆角是三者中最大的，视觉上最柔和、最有表达力。

---

## 6. Elevation（海拔系统）

M3 使用 **Surface Tint** 而非纯阴影来表达层次：

| Level | Tint Opacity | 阴影 | 用途 |
|-------|-------------|------|------|
| 0 | 0% | 无 | Surface 基础 |
| 1 | 5% | 微弱 | Card, Navigation Bar |
| 2 | 8% | 轻微 | Elevated Card |
| 3 | 11% | 中等 | FAB, Snackbar |
| 4 | 12% | — | 较少使用 |
| 5 | 14% | 明显 | Navigation Drawer |

### Surface Tint 实现

```css
/* 用 Primary 色做 overlay，opacity 按 level 递增 */
.elevation-1 {
  background: linear-gradient(
    rgba(var(--md-primary-rgb), 0.05),
    rgba(var(--md-primary-rgb), 0.05)
  ), var(--md-surface);
}
```

> **Dark 模式下 Surface Tint 更重要**——阴影在深色背景上几乎不可见，用 tint 区分层次。

---

## 7. Motion（动效系统）

### Duration

| 类型 | 时长 | 用途 |
|------|------|------|
| Short 1 | 50ms | 选中/取消选中 |
| Short 2 | 100ms | 简单状态切换 |
| Short 3 | 150ms | 小组件出现 |
| Short 4 | 200ms | 标准交互 |
| Medium 1 | 250ms | 面板展开 |
| Medium 2 | 300ms | 标准转场 |
| Medium 3 | 350ms | 复杂转场 |
| Medium 4 | 400ms | 全屏转场 |
| Long 1 | 450ms | 强调动画 |
| Long 2 | 500ms | 复杂强调 |
| Extra Long 1-4 | 700-1000ms | 极少使用 |

### Easing

```css
/* Standard — 不离开屏幕的移动 */
--md-standard: cubic-bezier(0.2, 0, 0, 1);
--md-standard-decelerate: cubic-bezier(0, 0, 0, 1);
--md-standard-accelerate: cubic-bezier(0.3, 0, 1, 1);

/* Emphasized — 更有表达力的移动 */
--md-emphasized: cubic-bezier(0.2, 0, 0, 1);
--md-emphasized-decelerate: cubic-bezier(0.05, 0.7, 0.1, 1);
--md-emphasized-accelerate: cubic-bezier(0.3, 0, 0.8, 0.15);
```

### 转场模式

| 模式 | 用途 | 示例 |
|------|------|------|
| Container Transform | 元素展开为页面 | 卡片 → 详情页 |
| Shared Axis | 同层级导航 | Tab 切换 |
| Fade Through | 无关联页面切换 | Bottom Nav 切换 |
| Fade | 简单出现/消失 | Dialog、Snackbar |

---

## 8. 导航模式

### 按设备选择

| 设备 | 推荐导航 | 组件 |
|------|---------|------|
| 手机（竖屏） | 底部导航 | Navigation Bar（3-5 项）|
| 手机（横屏） | 侧边导航 | Navigation Rail |
| 平板 | 侧边导航 | Navigation Rail / Drawer |
| 桌面/大屏 | 侧边导航 | Navigation Drawer（常驻）|
| 折叠屏 | 自适应 | Rail（折叠）→ Drawer（展开）|

### Navigation Bar（底部导航）

```
┌───────────────────────────────────┐
│                                   │
│          Content Area             │
│                                   │
├─────┬─────┬─────┬─────┬─────────┤
│  🏠  │  🔍  │  ➕  │  💬  │  👤    │
│ Home │Search│ Add │ Chat │Profile │
└─────┴─────┴─────┴─────┴─────────┘
```

- 3-5 个目的地
- 选中项显示 label + 指示器（pill 形状）
- 高度：80dp
- 指示器：64×32dp，圆角 16dp

### Navigation Rail（侧边窄导航）

```
┌──┬──────────────────────┐
│🏠│                      │
│──│                      │
│🔍│    Content Area      │
│──│                      │
│💬│                      │
│──│                      │
│⚙️│                      │
└──┴──────────────────────┘
```

- 宽度：80dp
- 可选 FAB 在顶部
- 选中项有 pill 指示器

---

## 9. Dark Theme

### M3 Dark Theme 规则

```
Surface: 极深灰（#1C1B1F），不是纯黑 #000000
On Surface: 极浅灰（#E6E1E5），不是纯白 #FFFFFF
```

| 原则 | 实践 |
|------|------|
| 避免纯黑 | Surface 用 `#1C1B1F`（Neutral Tone 6）|
| 减少大面积白色 | 用 Surface Tint 代替白色卡片 |
| 降低饱和度 | Primary 用更亮的色调（Tone 80） |
| 反转容器关系 | Light: 容器比背景浅 → Dark: 容器比背景浅（tint 更高）|

### 与 Apple Dark Mode 对比

```
Apple:    深灰 #1E1E1E，偏中性
Material: 极深灰 #1C1B1F，带紫色调（从 Neutral palette 来）
Apple:    不鼓励纯黑（但 OLED 用 #000000）
Material: 明确不推荐纯黑
```

---

## 10. 平台差异速查

| 差异点 | Material (Android) | Apple (iOS) |
|--------|-------------------|-------------|
| 主强调色 | Dynamic Color（壁纸取色） | System Blue #007AFF |
| 正文字号 | 16dp (Body Large) | 17pt (Body) |
| 按钮圆角 | 20dp（全圆角） | 无标准（偏 8-12px） |
| 对话框圆角 | 28dp | ~14px |
| 导航 | 底部 Navigation Bar | 底部 Tab Bar |
| 返回 | 系统返回手势/按钮 | 左上角 Back Button |
| 主操作 | FAB（浮动操作按钮） | Navigation Bar Button |
| 下拉刷新 | 有 | 有（Pull to Refresh） |
| Toast/提示 | Snackbar（底部，可操作） | Alert / Toast（中间/顶部） |
| 触控目标 | 48dp | 44pt |
| 标题栏 | Top App Bar（多样式） | Navigation Bar（标准） |

---

## 11. Checklist

### 设计审计
- [ ] 使用 M3 Color Scheme（Primary/Secondary/Tertiary + Surface 系列）
- [ ] 按钮用全圆角（20dp radius）
- [ ] Card 用 12dp 圆角
- [ ] Dialog 用 28dp 圆角
- [ ] 触控目标 ≥ 48dp
- [ ] 排版使用 M3 Type Scale
- [ ] Elevation 用 Surface Tint 而非纯阴影
- [ ] 导航选对设备模式（Bar / Rail / Drawer）
- [ ] 动画使用 M3 标准 easing

### Dark Theme
- [ ] Surface 不用纯黑（用 Neutral Tone 6）
- [ ] On Surface 不用纯白
- [ ] Primary 用 Tone 80（更亮）
- [ ] Surface Tint 可见
- [ ] 对比度 ≥ 4.5:1

### Android 开发
- [ ] 支持 Dynamic Color（Android 12+）
- [ ] 低版本 fallback 到静态配色
- [ ] 使用 MaterialTheme（Compose）或 Theme.Material3（XML）

---

## 来源

Material Design 3 (m3.material.io) + Material Theme Builder + Jetpack Compose 官方组件参考。
