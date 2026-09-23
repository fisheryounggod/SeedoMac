# Recordoo macOS App Store 发布完整教程

## 1. 发布链路

```text
源码与权限审计
  → Release Archive
  → 检查最终签名产物
  → Upload / Transporter
  → 出口合规
  → App Store Connect 元数据
  → App Information
  → App Privacy
  → 选择 Build
  → Add for Review
  → 最终 Submit to App Review
```

“上传成功”不等于“可送审”。App Store Connect 只有在二进制、截图、元数据、隐私、分类、年龄分级和审核信息都完整时才会启用 `Add for Review`。

## 2. Xcode 工程与版本号

发布前统一以下字段：

- `PRODUCT_BUNDLE_IDENTIFIER`: `tech.seedo.mac`
- App Store 版本：`CFBundleShortVersionString`，例如 `2.3.8`
- Build 号：`CFBundleVersion`，例如 `238`
- 产品名：Xcode target 的 `PRODUCT_NAME`，Recordoo 当前最终可执行文件名为 `Recordoo`

每次重新上传都必须增加 Build 号。同一版本可有多个 Build，但同一 Build 号不能重复上传。

## 3. App Sandbox 与 entitlements

Mac App Store 主可执行文件必须包含：

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```

Recordoo 当前功能还需要：

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.personal-information.calendars</key>
<true/>
```

不要只看源 `entitlements` 文件。Archive 或导出后必须检查最终 App：

```sh
codesign -d --entitlements - Recordoo.app
codesign --verify --deep --strict --verbose=2 Recordoo.app
```

错误 `90296 App sandbox not enabled` 说明最终签名产物中没有沙盒 entitlement，不是说 Xcode 界面上没有勾选。

### Accessibility 风险

Recordoo 使用 Accessibility API 读取其他应用窗口标题和浏览器 URL。开启 App Sandbox 后，必须用 Release 构建真实回归这两项功能。上传校验通过不代表跨进程访问仍然有效。

## 4. Info.plist 必要项

Mac App Store 要求有效的应用分类 UTI：

```xml
<key>LSApplicationCategoryType</key>
<string>public.app-category.productivity</string>
```

错误 `90242` 就是最终 `Info.plist` 缺少此项。验证时读产物，不读源文件：

```sh
plutil -p Recordoo.app/Contents/Info.plist
```

如果应用只使用 Apple 操作系统提供的 HTTPS/TLS，而没有实现自有或非豁免加密算法，可在核实后添加：

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

这可减少每个 Build 重复出现 `Missing Compliance`。该声明必须与实际加密用法一致，不能为了省步骤盲填 `false`。

## 5. Archive 与上传

1. Xcode 选择 `Any Mac` 或合适的 macOS 目标。
2. 执行 `Product → Archive`。
3. 在 Organizer 中选择 `Distribute App → App Store Connect → Upload`。
4. 等待 Build 在 App Store Connect 完成 `Processing`。
5. 处理出口合规问题，直到 Build 可被选中。

提交前保留 `.xcarchive`和 dSYM，便于后续崩溃符号化。

## 6. App Store 截图

macOS 应用截图可使用以下尺寸：

- `1280 × 800`
- `1440 × 900`
- `2560 × 1600`
- `2880 × 1800`

关键原则：

- 不拉伸 UI。
- 原图不是 16:10 时，优先等比缩放并用与应用背景一致的颜色补边。
- 裁切前检查四角按钮；Recordoo 的左上模式按钮和右上关闭按钮容易被误裁。
- 上传后以 App Store Connect 显示的文件名和数量为准。
- 应优先使用真实 App 截图。如果使用生成或修饰的界面图，必须与真实功能、文案和布局一致，不能展示 App 中不存在的功能。

ImageMagick 精确缩放示例：

```sh
magick input.png -resize 1280x800! -strip output_1280x800.png
identify -format '%w x %h\n' output_1280x800.png
```

## 7. 公开隐私政策与支持页

macOS App 必须提供公开可访问的 Privacy Policy URL，版本页还必须有 Support URL。Recordoo 使用 GitHub Pages：

- Privacy: `https://fisheryounggod.github.io/SeedoMac/privacy.html`
- Support: `https://fisheryounggod.github.io/SeedoMac/support.html`
- Marketing: `https://fisheryounggod.github.io/SeedoMac/`

源文件位于：

- `docs/privacy.html`
- `docs/support.html`
- `docs/index.html`

GitHub Pages 从 `main` 分支的 `/docs` 目录发布。推送后不要立即填 URL，先确认构建完成且返回 HTTP 200：

```sh
curl -sS -o /dev/null -w '%{http_code}\n' \
  https://fisheryounggod.github.io/SeedoMac/privacy.html
curl -sS -o /dev/null -w '%{http_code}\n' \
  https://fisheryounggod.github.io/SeedoMac/support.html
```

隐私政策必须说明：

- 本地保存的数据类型。
- 日历、Accessibility、通知和用户选择文件权限的用途。
- 用户主动配置 AI 服务时，哪些上下文会发送到该服务。
- Obsidian、日历和导出的数据边界。
- 数据删除方式和联系渠道。

## 8. 版本页元数据

简体中文本地化需填：

- Promotional Text，最多 170 字符。
- Description，最多 4,000 字符。
- Keywords，最多 100 字符，逗号分隔。
- Support URL，必填。
- Marketing URL，可选。
- Version。
- Copyright。

Recordoo 当前元数据要点：

- 定位：macOS 专注管理与工作复盘工具。
- 主要功能：番茄钟/正计时、休息提醒、活动追踪、离开检测、数据统计、AI 复盘、Obsidian 工作流。
- 隐私表述：本地优先；AI 由用户配置和主动触发，不要笼统声称“所有数据永不离开设备”。

## 9. App Information

### 分类

- Primary Category: `Productivity`
- `Info.plist` 中对应：`public.app-category.productivity`

App Store Connect 分类与 `Info.plist` 分类都要设置，它们是两个独立检查项。

### Content Rights

Recordoo 会在用户授权下访问日历、浏览器域名、窗口标题和 Obsidian 内容，因此保守申报为：

`Yes, this app has the necessary rights to its third-party content.`

这不是说开发者拥有所有用户内容，而是说应用只在用户授权和相应法律允许的范围内访问。

### 年龄分级

Recordoo 不含社交、聊天、广告、无限制网页浏览、暴力、性内容或赌博。但休息提醒包含“起身活动、放松眼睛和肩颈”等生活方式建议，因此：

- `Health or Wellness Topics`: Yes
- `Medical or Treatment Information`: None
- 其他题目：No / None

该答案在当前问卷中计算为全球 `9+`，部分地区会根据本地标准显示不同等价分级。

## 10. App Privacy 问卷

Apple 的问卷对“Collect”的定义是：数据离开设备，且开发者或集成代码的第三方伙伴能在完成实时请求所需时间之外继续访问。

Recordoo 当前：

- 没有广告或分析 SDK。
- 没有开发者运营的数据接收服务器。
- AI 地址和密钥由用户自行配置，应用仅代用户发起实时请求。

因此当前回答：

`No, we do not collect data from this app.`

但隐私政策仍明确披露了可选 AI 数据传输。如果以后增加默认后端、分析 SDK、崩溃上报、账号系统或服务端保留，必须立即重新评估并更新 App Privacy。

填完后还要点击 `Publish`。仅保存为草稿不会解除送审阻塞。

## 11. Build、审核信息与发布方式

版本页需要：

- 选择已处理完的 Build，Recordoo 当前为 `2.3.8 (238)`。
- 如果 App 不需要登录，取消 `Sign-in required`，不要留空用户名和密码。
- 填写审核联系人姓名、电话和邮箱。
- Notes 中可说明 Accessibility、日历、用户选择文件、AI 自配置等功能的测试步骤。
- 如果功能难以复现，上传审核附件或录屏。

发布方式可选：

- 审核通过后手动发布。
- 审核通过后自动发布。
- 审核通过后不早于指定时间发布。

首次发布更建议使用手动发布，便于在上架前再检查价格、地区、公开页面和下载状态。

## 12. 送审前最终检查清单

### 二进制

- [ ] Release Archive 使用正确的 Distribution 签名。
- [ ] Bundle ID、Version 和 Build 与 App Store Connect 一致。
- [ ] 最终可执行文件含 `app-sandbox = true`。
- [ ] 最终 `Info.plist` 含有效 `LSApplicationCategoryType`。
- [ ] 所有申报的 entitlement 都与实际功能一致。
- [ ] 沙盒 Release 构建已回归日历、文件、网络和 Accessibility 功能。

### 产品页

- [ ] 截图尺寸符合 macOS 规格，内容与真实 App 一致。
- [ ] 描述、关键词、Support URL 和版权信息已保存。
- [ ] Privacy 和 Support 页面从未登录浏览器也能打开。
- [ ] 主分类为 Productivity。
- [ ] Content Rights 已设置。
- [ ] Age Ratings 已完成并保存。
- [ ] App Privacy 已发布，不是仅保存草稿。

### 审核

- [ ] Build 已选择且没有 `Missing Compliance`。
- [ ] 登录需求与实际 App 一致。
- [ ] 审核联系人姓名、电话和邮箱完整。
- [ ] 审核 Notes 能让审核员复现核心功能。
- [ ] 发布方式已确认。
- [ ] `Add for Review` 已启用。
- [ ] 点击最终 `Submit to App Review` 前再做一次全页检查。

## 13. 常见报错对照

| 报错 | 根因 | 修复 |
|---|---|---|
| `90296 App sandbox not enabled` | 最终签名可执行文件没有沙盒 entitlement | 在 target 引用的 entitlements 中启用 App Sandbox，重新 Archive，然后检查产物 |
| `90242 LSApplicationCategoryType` | 最终 Info.plist 没有应用分类 UTI | 添加 `public.app-category.productivity` 并重新 Archive |
| Screenshot dimensions wrong | 截图不在 Apple 允许的 macOS 尺寸集合中 | 转换为 1280×800、1440×900、2560×1600 或 2880×1800 |
| Privacy Policy URL required | App Privacy 没有公开 URL | 发布隐私页，验证 HTTP 200，在 App Privacy 填写 |
| Admin must provide privacy practices | 隐私问卷未完成或未 Publish | 用 Admin/App Manager 完成数据问卷并点击 Publish |
| Primary category required | App Store Connect 的 Primary Category 为空 | 在 App Information 选择 Productivity 并 Save |
| Content Rights required | 内容权利问卷未设置 | 根据实际功能回答并 Save |
| Age ratings required | 年龄分级问卷未完成 | 完成所有步骤，不能只填第一页 |
| Support URL required | 当前本地化的 Support URL 为空 | 在版本页选中对应语言后填写并 Save |
| Missing Compliance | Build 的加密出口合规未声明 | 根据真实加密用法回答；如符合豁免条件，在 Info.plist 正确设置 `ITSAppUsesNonExemptEncryption` |

## 14. 本次 Recordoo 发布状态

截至 2026-08-28：

- GitHub Pages 已启用，Privacy 和 Support URL 均返回 HTTP 200。
- Primary Category 已设为 Productivity。
- Content Rights 已设置。
- Age Rating 已完成，计算结果为 9+。
- App Privacy 已发布为 Data Not Collected。
- Build `2.3.8 (238)` 已关联。
- 版本页必填阻塞已解除，`Add for Review` 已启用。
- 审核联系人电话和邮箱仍应在最终提交前补齐。
- 尚未执行最终 `Add for Review` / `Submit to App Review`。
