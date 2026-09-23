# SeedoMac 手动记录输入焦点修复经验

## 问题

手动记录窗口由菜单栏应用创建，普通 `NSWindow` 在显示后不一定成为 Key/Main Window。SwiftUI 的 `FocusState` 可能在窗口激活前执行，造成输入框没有光标，中文输入法无法工作，文本也无法正常选中。

## 修复

- 手动记录窗口改用可成为 Key/Main Window 的 `KeyWindow`。
- 首次显示和窗口重新成为 Key Window 时，都在下一个主线程 RunLoop 中重新设置标题输入框焦点。
- 保留 SwiftUI 原生 `TextField` / `TextEditor`，让 AppKit 输入法和文本选择链路正常工作。
