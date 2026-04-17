这是一个基于 Swift 开发的 macOS 原生应用，旨在通过自动活动追踪和 AI 分析来提升个人效率。


1. 核心功能与架构

- 活动追踪 (Tracker)：通过 1 秒一次的轮询监听前台应用。支持 AFK（离开）检测、窗口标题抓取（Accessibility API）以及针对主流浏览器的 URL 提取。
- AI 效率教练 (AI Service)：集成 OpenAI 兼容接口，根据每日使用数据（Top 应用、时间分配、分类统计）生成简洁的工作复盘，并给出 专注评分。
- 本地存储 (Persistence)：使用 GRDB.swift 操作 SQLite 数据库。所有记录（Events）、分类（Categories）和 AI 总结（Daily Summaries）均存储在本地。
- Obsidian 集成：内置 ObsidianImporter，可定期同步 Obsidian 中的数据。

1. 技术栈
语言：Swift 5.10 (Target macOS 13.0+)
界面：SwiftUI + AppKit (常驻菜单栏 NSStatusItem 架构)
项目管理：使用 XcodeGen (project.yml) 自动生成工程文件。

1. 项目结构概览
/App: 处理 AppDelegate 生命周期及全局状态。
/Tracker: 包含核心追踪逻辑、浏览器/窗口信息提供者。
/AI: 处理 LLM 请求、Prompt 构建及密钥安全（Keychain）。
/Data: 定义数据库模型、SQL 迁移逻辑及 Obsidian 导入器。
/Views: SwiftUI 界面，包括菜单栏弹窗及主仪表盘。