# Seedo 2.0.1 - 智能专注管理中心

Seedo 是一款专为 macOS 设计的首位一体化专注力管理工具。它集成了**静默活动追踪**、**深色模式沉浸计时**、**AI 智能复盘**以及 **Obsidian 数字化同步**，旨在帮助用户达成极致的生产力闭环。

---

## 🏗 架构设计与实现思路

### 1. 核心技术栈
- **Frontend**: SwiftUI (原生 macOS 开发，确核极致性能与系统一致性)
- **Backend Architecture**: 组件化单例模式 (App State, App Database, Activity Tracker)
- **Persistence**: [GRDB.swift](https://github.com/groue/GRDB.swift) + SQLite (本地持久化，确核数据隐私)
- **AI Engine**: 集成 Google Gemini API (非结构化数据清洗与生产力评估)

### 2. 核心模块实现

#### A. 静默活动追踪 (Activity Tracker)
- **工作原理**: 通过定时轮询 macOS 全局事件（窗口切换、活动应用），记录用户在不同 App 及网站上的停留时长。
- **隐私保护**: 所有的追踪数据物理存储在用户本地 `~/Library/Application Support/Seedo/seedo.db` 中，不上传云端。
- **AFK 检测**: 物理监听系统空闲状态。当检测到用户长时间无操作时，物理暂停追踪，并弹出“返岗确认”，确核记录的物理精准度。

#### B. 深度模式 (DeepFocus) - **v2.0.1 重点更新**
- **交互演进**:
    - **Pill-Style Toggle**: 2.0.1 版引入了单点切换逻辑。用户只需点击计时模式标签，即可物理循环切换“蕃茄钟”与“正计时”。
    - **多屏物理屏蔽**: 物理提升窗口级别至 `.screenSaver`。开启后将物理覆盖所有连接的显示器：
        - **主屏**: 提供全功能计时器与操作区。
        - **副屏**: 展示幽静的背景，物理屏蔽所有视觉干扰，确核 100% 的沉浸感。

#### C. AI 智能复盘与 Obsidian 同步
- **Context 语义分析**: 系统将全天的 App 活跃数据、手动记录的专注片段物理喂给 AI，生成一段高度精炼的生产力评估。
- **Obsidian 同步**: 
    - 物理适配 Obsidian 核心日记逻辑。
    - **自定义正则解析**: 用户可在设置中物理定义 `obsidian_import_regex`，确核软件能从复杂的日记模板中物理抓取并反向复盘工作内容。

---

## 📂 数据库 Schema 概览

Seedo 使用 SQLite 存储核心数据点：
- `events`: 原子活动记录 (App, Title, Duration)
- `work_sessions`: 专注片段记录 (Start, End, Category, Summary)
- `categories`: 自定义分类 (工作, 日常, 干扰)
- `daily_summaries`: AI 生成的每日精华建议

---

## 🚀 版本演进 (v2.0.1)

- **[New]** 深色模式支持物理覆盖所有连接的显示器。
- **[New]** 深度专注窗口级别物理升级至 `.screenSaver`，真正做到“覆盖一切”。
- **[Opt]** 蕃茄钟与正计时切换逻辑简化为单点 Toggle。
- **[Fix]** 优化了多屏环境下的全屏显示稳定性。

---

## 🛠 开发与构建指南

### 环境依赖
- macOS 14.0+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (推荐使用 `project.yml` 生成工程)

### 构建命令
```bash
# 生成 Xcode 项目
xcodegen generate

# 构建并打包成果物
bash build_dmg.sh
```

---

## 📝 许可证
Seedo 2.0.1 遵循内部闭源/个人分发协议。版权所有 © 2026 Seedo Team.