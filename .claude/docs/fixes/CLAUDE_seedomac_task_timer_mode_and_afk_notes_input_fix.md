# SeedoMac 任务计时模式联动与离席 Notes 中文输入修复

日期：2026-09-21

## 问题

今日任务的“番茄”和“开始”按钮都调用任务启动函数，而旧启动函数无条件 `resetWork()`。因此同一个任务从番茄钟切到正计时，累计秒数、会话起点和跳过休息累计都会丢失，看起来像重新开始。

离席检测窗口使用普通 `NSWindow` 和单一摘要焦点。菜单栏应用在窗口刚展示时可能尚未成为 Key Window，Notes 的 SwiftUI `TextEditor` 没有独立的 FocusState，中文输入法无法稳定获得 first responder。

## 修复

- `BreakScheduler.startTask` 对比标准化后的任务标题。同一任务只切换 `timerMode` 并保存状态，保留已用秒数、会话起点、累计跳过时间和任务绑定；切换到不同任务才创建新计时。
- 今日任务按钮改为“番茄 / 正计时”，同一任务的当前模式显示进行中状态，帮助文案明确提示切换会保留进度。
- 离席窗口改用 `KeyWindow` 和 `NSHostingController`，展示后再次激活并置为 Key，避免菜单栏应用抢焦点。
- AFK 表单给摘要和 Notes 分别绑定 `FocusedField`，窗口成为 Key 后仅在没有焦点时请求摘要焦点；Notes 使用同时手势设置焦点，不吞掉 TextEditor 原生光标与选区操作，中文 IME 可正常输入。

## 验证

- Debug 构建通过。
- XCTest 全部通过：22 tests、0 failures。
- 已生成并安装验证包 `Seedo_v2.3.12.dmg`（Build 242），应用代码签名通过。
- 新增 `TaskTimerModeTests`：验证同一任务切换模式保留 325 秒进度；切换到不同任务会清零并绑定新任务。
- 编译期间仍有本机 Xcode/CoreSimulator 组件版本提示和既有 SwiftUI `onChange` 弃用警告，不影响 macOS 构建和测试结果。

## 经验

计时模式是同一会话的展示方式，任务身份和计时累计必须独立于模式。菜单栏应用中的文本输入问题，不能只在 SwiftUI 视图上设置 `focused`；必须同时保证宿主窗口可成为 Key，并在窗口真正激活后再请求焦点。
