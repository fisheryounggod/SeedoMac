# SeedoMac 可选全局快捷键修复经验

## 问题

SeedoMac 使用 `KeyboardShortcuts` 注册跨应用快捷键，但设置页没有总开关。用户可以录入快捷键，却无法停用全局监听；同时，应用内菜单快捷键不应被这个选项影响。

## 修复

- 增加 `global_shortcuts_enabled` 设置，缺失时默认启用以兼容已有用户。
- 使用 `KeyboardShortcuts.isEnabled` 控制 Carbon 全局事件监听。
- 设置保存后立即应用开关，不需要重启应用。
- 保留快捷键录入；关闭时只停用跨应用监听，Seedo 菜单中的本地快捷键仍可用。
- 用 `KeyboardShortcuts.Name.allSeedoShortcuts` 集中维护快捷键清单，避免后续停用逻辑遗漏。
