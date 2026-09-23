# SeedoMac App Store 沙盒与分类元数据修复

## 现象

- App Store Connect 报错 `90296`：主可执行文件没有启用 App Sandbox。
- App Store Connect 报错 `90242`：应用 `Info.plist` 缺少 `LSApplicationCategoryType`。

## 根因

Xcode target 已通过 `CODE_SIGN_ENTITLEMENTS` 引用 `SeedoMac/Seedo.entitlements`，但该文件是空字典，因此最终签名的主可执行文件不包含 `com.apple.security.app-sandbox = true`。源 `Info.plist` 也没有 Mac App Store 必需的分类 UTI。

## 修复

- 启用 `com.apple.security.app-sandbox`。
- 按当前功能补充出站网络、用户选择文件读写和日历访问 entitlement。
- 将 `LSApplicationCategoryType` 设为 `public.app-category.productivity`。

## 验证

不要只检查源 plist；必须检查 Archive/导出后的最终产物：

```sh
codesign -d --entitlements :- Recordoo.app
plutil -p Recordoo.app/Contents/Info.plist
```

前者应显示 `com.apple.security.app-sandbox = true`，后者应显示 `LSApplicationCategoryType = public.app-category.productivity`。

## 限制

Recordoo 使用 Accessibility API 读取其他应用窗口标题和浏览器 URL。App Sandbox 可能使这类跨进程访问失效；上传前应使用 Release 沙盒构建单独回归该功能，不应为了通过元数据检查而假定功能仍然可用。
