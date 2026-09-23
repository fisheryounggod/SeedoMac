# SeedoMac 右键菜单与全局快捷键统一经验

## 问题

菜单栏图标右键菜单使用写死的快捷键，而全局快捷键使用 `KeyboardShortcuts.Recorder` 独立配置，导致设置页修改后两处显示和行为不一致。

## 修复

- 右键菜单通过 `NSMenuItem.setShortcut(for:)` 读取同一组 `KeyboardShortcuts.Name`。
- 新增“结束并记录”快捷键配置，并纳入全局快捷键清单。
- 菜单跟踪期间停用 Carbon 全局监听，菜单关闭后按设置恢复，避免一次按键触发两次。
- 退出保留菜单专用，不提供全局退出快捷键，降低误退出风险。

## 构建兼容性

`KeyboardShortcuts.NSMenuItem.setShortcut(for:)` 是 `@MainActor` API；调用它的菜单创建和菜单代理回调也必须显式标注 `@MainActor`，否则在 Release/Archive 编译时会出现隔离错误。修复后需用 `build_dmg.sh` 完整归档验证，而不是只依赖 Debug 编译。
