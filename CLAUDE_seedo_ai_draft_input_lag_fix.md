# SeedoMac 复盘输入卡顿修复经验

## 问题
Dashboard 的“深度复盘与心得”输入框绑定 `aiDraftContent`，并在 `.onChange` 中直接调用 `AppDatabase.shared.saveSetting`。这会导致每输入一个字符都同步触发一次 SQLite 写入，长文本输入时主线程和 SwiftUI diff 压力明显升高。

## 修复
- 增加 `draftSaveTask`，用 `DispatchWorkItem` 对草稿保存做 0.8 秒防抖。
- 实际 SQLite 写入切换到 `DispatchQueue.global(qos: .utility)`。
- 增加 `isLoadingDraft`，避免加载草稿时触发反向保存。
- 正式保存 AI 复盘前取消未执行的草稿保存任务，防止旧草稿延迟回写。

## 经验
输入框绑定的 `.onChange` 不能直接做持久化 I/O。高频输入路径应该只更新内存，持久化必须防抖、后台化，必要时在失焦、关闭窗口或点击保存时立即 flush。
