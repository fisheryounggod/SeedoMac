# SeedoMac 今日任务绑定与直接记录修复经验

## 问题

“今日任务”的开始按钮只把任务名写入 `AppState.currentTitle`。这个字段由
`ActivityTracker` 持续更新为当前前台窗口标题，因此专注结束时任务内容已经丢失，
停止动作只能再次弹出手动记录表单。

## 修复

- 在 `BreakScheduler` 增加独立的 `boundTaskTitle` 会话字段，并随计时器恢复状态持久化。
- “番茄”和“开始”统一调用 `startTask(_:mode:)`，启动时绑定任务名，不再改写窗口追踪标题。
- 绑定任务结束时调用 `stopAndRecordBoundTask`，直接创建 `WorkSession`（标题为任务名、类别为 `focus`）；未绑定的普通计时仍走手动记录流程。
- 纯专注模式停止同样走直接保存路径；保存失败才回到可重试的记录界面。
- 普通计时区与纯专注表盘显示当前绑定任务，点击后可立即确认绑定结果。
- 菜单/快捷键停止前先刷新活动缓冲，保证专注记录的应用快照包含最后一段活动。
- 番茄倒计时自然结束时先直接保存绑定任务，再跳过回顾询问、直接进入休息倒计时；休息结束只清理状态，不重复写入同一专注记录。

## 验证

- `swiftc -parse` 通过涉及的 Swift 文件。
- `xcodebuild -project Seedo.xcodeproj -scheme Seedo -configuration Debug -destination 'platform=macOS' build` 通过。
- `xcodebuild -project Seedo.xcodeproj -scheme Seedo -destination 'platform=macOS' test` 通过：20 项测试，0 失败。
