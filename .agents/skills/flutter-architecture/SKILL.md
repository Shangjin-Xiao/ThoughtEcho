---
name: flutter-architecture
tags: flutter, architecture, mvvm, scaffold, template
description: Flutter 四层组件化 + MVVM 项目架构规范。适用于 Flutter 项目开发、新模块创建、目录结构设计、代码评审、架构对齐。支持在项目中直接创建/搭建整套 MVVM+组件化目录结构。
---

# Flutter 组件化 + MVVM 架构规范

## 核心架构

**四层纵向依赖**（严格单向）：

```
app → business → component → foundation
```

**业务模块内 MVVM**：

```
View (page/view) → ViewModel → Repository → Model
```

## 层级职责速查

| 层级 | 职责 |
|------|------|
| **app** | 主工程层：全局配置、路由、启动项、模块编排，无业务逻辑 |
| **business** | 业务组件层：强业务实现，按模块拆分，模块间通过路由通信 |
| **component** | 功能组件层：公司/团队通用能力（支付、分享、推送等），与业务有一定绑定 |
| **foundation** | 基础组件层：与公司/项目无关的底层能力，强可移植性 |

## 业务模块目录结构

```
{module}/
├── page/           # 页面：xxx_page.dart → XxxPage
├── view/           # 视图：xxx_view.dart、xxx_navigation_bar.dart 等
├── view_model/
├── model/
└── repository/
```

## Page / View 命名（强制）

- **page**：文件 `xxx_page.dart`，类 `XxxPage`
- **view**：常规视图 `xxx_view.dart` → `XxxView`；功能型 `xxx_navigation_bar.dart` → `XxxNavigationBar`
- **严禁**：禁止使用 `widget` 关键字

## 依赖规则（严禁违反）

- 上层可依赖下层，下层不可依赖上层
- 同级业务不互相 import，仅通过路由通信
- 依赖链唯一：`app → business → component → foundation`

## 目录创建能力（Scaffold）

当用户要求**创建目录结构**、**搭建架构**、**新建模块**、**scaffold** 时，在项目 `lib/` 下直接创建以下结构：

**全量创建**（新项目或完整搭建）：
- `lib/app/config/`、`lib/app/pages/`
- `lib/business/{module}/` 下每个模块含 `page/`、`view/`、`view_model/`、`model/`、`repository/`
- `lib/component/`（可含 pay、share、push、update 等子目录）
- `lib/foundation/`（network、image、router、db、utils、base 等）

**增量创建**（新增业务模块）：
- 在 `lib/business/` 下创建 `{module_name}/page/`、`view/`、`view_model/`、`model/`、`repository/`
- 模块名使用小写下划线（如 home、user_profile、scenario_learning）

创建时按 [references/architecture.md](references/architecture.md) 中的完整目录结构执行，确保层级与命名符合规范。

## 完整规范

详细目录结构、各层说明、MVVM 职责、命名规范、代码示例、Code Review 标准见 [references/architecture.md](references/architecture.md)。
