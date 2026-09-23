# Claude 指令

## 问题修复索引

- [SeedoMac 任务计时模式联动与离席 Notes 中文输入修复](./.claude/docs/fixes/CLAUDE_seedomac_task_timer_mode_and_afk_notes_input_fix.md) - 同一任务切换番茄钟/正计时保留进度；离席窗口改用 Key Window、独立 Notes 焦点与中文 IME 兼容

- [SeedoMac 今日任务绑定与直接记录](./.claude/docs/fixes/CLAUDE_seedomac_today_task_binding_direct_record.md) - 今日任务启动时独立保存会话任务名，避免被前台窗口标题覆盖；绑定任务结束时直接写入专注记录，不再弹出手动输入

- [SeedoMac UI 重整与休息页自然布局](./.claude/docs/fixes/CLAUDE_seedomac_ui_refresh_flow_layout.md) - 解除底部固定、目标移至回顾下方、不透明休息背景；统一明暗配色与控件，统计页自适应；取代旧固定底栏约定

- [SeedoMac 休息倒计时居中与纯专注时钟适配](./.claude/docs/fixes/CLAUDE_seedomac_countdown_viewport_centering.md) - 按底部操作栏上方实际视口居中；切换阶段重置滚动；纯专注表盘和长时间数字自适应

- [SeedoMac 今日目标提醒与编辑](./.claude/docs/fixes/CLAUDE_seedomac_today_goal_reminders.md) - 当日目标准确判断、提醒任务文案、共享添加与双击编辑界面

- [SeedoMac 右键菜单与全局快捷键统一](./.claude/docs/fixes/CLAUDE_seedomac_context_menu_shortcuts_unification.md) - 右键菜单读取同一套可配置快捷键；新增结束并记录配置；菜单跟踪期间避免全局回调重复触发
- [SeedoMac 提醒页底部操作区布局](./.claude/docs/fixes/CLAUDE_seedomac_break_overlay_bottom_actions.md) - 固定提醒页底部按钮栏，避免长内容将确认操作挤出全屏窗口
- [SeedoMac 手动记录输入焦点](./.claude/docs/fixes/CLAUDE_seedomac_manual_record_text_input_focus.md) - 菜单栏应用窗口可靠成为 Key/Main Window；窗口激活后重新聚焦输入框，修复光标、中文输入和选中
- [SeedoMac 可选全局快捷键](./.claude/docs/fixes/CLAUDE_seedomac_optional_global_shortcuts.md) - 增加全局快捷键总开关；停用跨应用监听但保留应用内菜单快捷键；缺失配置默认兼容启用
- [SeedoMac 小屏布局、独立窗口与快捷键修复](./.claude/docs/fixes/CLAUDE_seedomac_compact_layout_independent_windows_shortcuts_fix.md) - 固定暂停操作栏；手动记录与设置独立展示；可靠预填、异步保存与键盘操作；附编译验证和离席/多屏/测试入口审查风险
- [Recordoo macOS App Store 发布完整教程](./.claude/docs/fixes/CLAUDE_recordoo_macos_app_store_release_guide.md) - 从 Archive 签名、沙盒、截图、GitHub Pages 隐私页到 App Store Connect 元数据、分级、隐私标签与送审的端到端检查清单
- [SeedoMac App Store 沙盒与分类元数据修复](./.claude/docs/fixes/CLAUDE_seedomac_app_store_sandbox_metadata_fix.md) - 修复 90296 沙盒 entitlement 缺失和 90242 应用分类缺失，并记录最终签名产物验证方法
- [SeedoMac 复盘输入卡顿修复经验](./CLAUDE_seedo_ai_draft_input_lag_fix.md) - TextEditor 逐字写 SQLite 导致输入卡顿，改为防抖后台保存
- [SeedoMac 纯专注模式误触切换计时修复经验](./CLAUDE_seedo_deep_focus_mode_switch_fix.md) - 早期二次确认方案，现已被共享计时状态方案替代
- [SeedoMac 纯专注与普通计时无缝切换修复经验](./CLAUDE_seedo_focus_surface_seamless_switch_fix.md) - 统一计时数据源，界面和模式切换不再暂停、重置或丢失倒计时
- [SeedoMac 长时间运行性能退化修复经验](./CLAUDE_seedo_long_running_performance_fix.md) - 拆分秒级 UI 与低频统计、合并事件碎片、优化索引与资源回收
