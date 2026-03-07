# Flutter 组件化 + MVVM 项目架构规范

**适用平台**：Flutter（Dart）  
**核心思想**：四层纵向分层 + 业务横向模块化 + MVVM 分层内聚  
**定位**：中大型项目长期迭代架构，降低理解成本、避免过度抽象

---

## 一、架构总览

本架构分为 **四层纵向依赖结构**，从上到下依次为：

| 层级           | 说明       |
| -------------- | ---------- |
| **app**        | 主工程层   |
| **business**   | 业务组件层 |
| **component**  | 功能组件层 |
| **foundation** | 基础组件层 |

**依赖方向**（严格单向，不可反向）：

```
app → business → component → foundation
```

每个业务模块内部采用标准 **MVVM**：

```
View → ViewModel → Repository → Model
```

---

## 二、完整项目目录结构（全量最终版）

```
lib/
├── main.dart                      # 应用入口
│
├── app/                           # 主工程层：全局配置 & 路由 & 根容器
│   ├── config/
│   │   ├── app_config.dart        # 全局配置：主题/环境/日志
│   │   └── router_config.dart     # 路由总配置
│   └── pages/
│       └── root_page.dart        # 应用根页面（Tab 容器/主框架）
│
├── business/                      # 业务组件层（按业务模块拆分）
│   ├── home/                      # 示例：首页模块（单页面）
│   │   ├── page/                  # 页面
│   │   │   └── home_page.dart
│   │   ├── view/                  # 视图（页面内子组件）
│   │   │   ├── home_item_view.dart
│   │   │   └── home_navigation_bar.dart
│   │   ├── view_model/
│   │   │   └── home_view_model.dart
│   │   ├── model/
│   │   │   └── home_model.dart
│   │   └── repository/
│   │       └── home_repository.dart
│   │
│   └── user/                      # 示例：用户模块（多页面/子模块）
│       ├── profile/               # 子模块：个人信息
│       │   ├── page/
│       │   ├── view/
│       │   ├── view_model/
│       │   ├── model/
│       │   └── repository/
│       ├── settings/              # 子模块：设置
│       │   ├── page/
│       │   ├── view/
│       │   ├── view_model/
│       │   └── model/
│       └── security/              # 子模块：安全中心
│           ├── bind_phone/
│           │   ├── page/
│           │   ├── view/
│           │   └── view_model/
│           └── change_pwd/
│               ├── page/
│               ├── view/
│               └── view_model/
│
├── component/                     # 功能组件层（公司/团队通用能力）
│   ├── pay/                       # 支付
│   │   ├── api/
│   │   ├── impl/
│   │   ├── model/
│   │   └── utils/
│   ├── share/                     # 分享
│   ├── push/                      # 推送
│   └── update/                    # 版本更新
│
└── foundation/                    # 基础组件层（底层技术能力）
    ├── network/
    │   ├── dio_config.dart
    │   └── base_api.dart
    ├── image/
    ├── router/
    ├── db/
    ├── utils/
    └── base/                      # 可选：基类（视技术选型而定，非必须）
        ├── base_view.dart
        └── base_view_model.dart
```

---

## 三、各层职责说明

> 以下按依赖顺序自下而上说明：foundation（最底层）→ component → business → app（最上层）

### 3.1 foundation — 基础组件层

基础组件层承载的是**与公司、团队、项目完全无关**的底层能力。可以是第三方开源库的封装，也可以是团队自研的通用基础能力。这些能力具备**强可移植性**：无论拿到哪个公司、哪个工程都可以直接使用，不包含任何业务逻辑。

**典型内容：**

- 网络封装（Dio 配置、请求基类）
- 图片加载、数据库、路由工具
- 通用工具类、扩展方法
- 可选：全局基类（如 BaseView / BaseViewModel，视团队技术选型而定）

### 3.2 component — 功能组件层

功能组件层是对**公司 / 团队 / 项目**通用能力的封装（可能依赖 foundation 层）。例如支付、分享、推送、统计、定位、版本更新等。这些能力在公司 / 团队内可以通用，但拿到其他公司使用时，往往需要针对 UI、流程、参数等做调整，与公司项目、业务之间存在**一定的绑定关系**。

**典型内容：**

- 支付、分享、推送、更新等能力模块
- 对外通过 api 暴露能力，内部 impl 实现细节隔离

### 3.3 business — 业务组件层

业务组件层是**强业务实现**。这里的组件（或模块）代码基本只在本项目中有效，拿到其他项目中几乎完全不可用，因为强业务本身不具备通用性。

**职责：**

- 按业务功能拆分为独立模块：home、user、login、order 等
- 每个模块独立维护自己的 UI、逻辑、数据
- 模块之间不直接依赖，通过路由跳转

**规范：**

- 单页面模块：直接使用 page、view、view_model、model、repository
- 多页面模块：按子页面 / 子功能继续拆分成文件夹
- 子模块最多嵌套一级，保持结构扁平

### 3.4 app — 主工程层

主工程层是应用的**最上层**，也是**入口层**。这里不包含业务实现，主要承担：

- **全局配置**：启动项、主题、环境、日志等
- **初始化与监听**：各业务模块、功能组件的初始化配置和监听
- **逻辑串联编排**：不同业务模块之间的协调与编排
- **应用根容器**：主 Tab 页面、路由总配置

**约束：**

- 不编写任何业务逻辑
- 只依赖 business + component（通过 component 间接依赖 foundation）

---

## 四、MVVM 分层职责（团队统一标准）

### 4.1 View

- 只负责 UI 渲染、事件响应
- 不写业务逻辑
- 监听 ViewModel 状态刷新界面

### 4.2 ViewModel

- 唯一业务逻辑入口
- 管理页面状态
- 调用 Repository 获取数据
- 不持有 BuildContext / Widget

### 4.3 Repository

- 统一数据入口
- 封装网络请求、本地缓存、数据聚合
- 不写业务逻辑

### 4.4 Model

- 数据结构定义
- 实体 / DTO
- 无行为逻辑

---

## 五、目录结构规范（强制执行）

1. **一个页面 / 子功能 = 一个独立文件夹**，包含自己的 page、view、view_model、model
   - **page**：页面级 Widget，对应路由可直接打开的完整页面
   - **view**：视图级 Widget，页面内的子组件、列表项、卡片等可复用 UI 片段
   - **命名规范**：page 固定以 `_page` 结尾，view 根据功能命名（见第十一章 11.6）
2. **公共代码放在模块根目录**
3. **子模块最多嵌套一级**，禁止深层嵌套
4. **业务组件之间不互相引用**，只能通过路由通信
5. **所有 Widget 只在 Page/View 层创建**，ViewModel 只做逻辑，不做 UI

---

## 六、依赖规则（严禁违反）

- 上层可以依赖下层
- 下层不能依赖上层
- 同级业务不能互相依赖
- 依赖链唯一：`app → business → component → foundation`

---

## 七、项目命名规范（强制统一）

### 11.1 文件夹命名（小写下划线）

| 类型       | 示例                                                   |
| ---------- | ------------------------------------------------------ |
| 业务模块   | home、user、login、order、mine                         |
| 子模块     | profile、settings、security、bind_phone                |
| 固定分层   | page、view、view_model、model、repository             |
| 功能组件层 | pay、share、push、update（位于 component 下）          |
| 基础组件层 | network、db、router、utils、base（位于 foundation 下） |

### 11.2 文件命名（小写下划线，见名知意）

| 类型     | 示例                         |
| -------- | ---------------------------- |
| 页面     | home_page.dart               |
| 视图模型 | home_view_model.dart         |
| 数据模型 | home_model.dart              |
| 仓库     | home_repository.dart         |
| 工具     | date_utils.dart              |
| 基类     | base_view_model.dart         |

### 11.3 类命名（大驼峰）

| 类型       | 示例           |
| ---------- | -------------- |
| 页面       | HomePage       |
| ViewModel  | HomeViewModel  |
| Model      | HomeModel      |
| Repository | HomeRepository |
| 基类       | BaseViewModel  |

### 11.6 Page / View 命名规范（强制，用于快速区分组件作用）

**页面（page 目录）：**

- **文件**：`xxx_page.dart`，固定以 `_page` 结尾
- **类**：`XxxPage`，固定以 `Page` 结尾
- 示例：`home_page.dart` → `HomePage`

**视图（view 目录）：**

- **文件**：根据功能命名，如 `xxx_view.dart`、`xxx_navigation_bar.dart`、`xxx_segment_control.dart`、`xxx_card.dart` 等
- **类**：与文件名对应，如 `XxxView`、`XxxNavigationBar`、`XxxSegmentControl`、`XxxCard` 等
- **常规视图**：若为通用展示型视图，以 `View` 作为最后一个单词，如 `home_item_view.dart` → `HomeItemView`
- **功能型视图**：若为导航栏、分段控件等有明确功能的组件，以功能名结尾，如 `home_navigation_bar.dart` → `HomeNavigationBar`

**严禁：**

- 禁止使用 `widget` 关键字命名文件或类（如 ~~home_item_widget.dart~~、~~HomeItemWidget~~）

---

## 十二、团队开发约束（Code Review 标准）

1. View 中不写业务逻辑，逻辑必须放在 ViewModel
2. ViewModel 禁止持有 BuildContext，禁止操作 UI
3. 网络 / 数据库操作必须写在 Repository
4. 业务模块之间禁止互相 import，只能通过路由跳转
5. 所有页面必须使用统一 MVVM 结构，禁止自定义结构
6. 多页面必须拆分子模块，禁止堆在同一个文件夹
7. 命名必须遵守规范，禁止拼音、缩写、无意义命名；Page/View 禁止使用 `widget` 关键字
8. 子模块嵌套最多一级，保持结构扁平

---

## 文档说明

本文档中的 BaseView、BaseViewModel 等 MVVM 相关代码仅为**示例说明**，实际项目中可根据所选状态管理方案（Provider、Riverpod、GetX 等）自行决定是否引入基类，无需强制实现。
