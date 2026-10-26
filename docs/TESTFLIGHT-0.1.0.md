# Being Town 0.1.0 TestFlight

日期：2026-10-23（Asia/Shanghai）。

## 当前构建：0.1.0 (7)

- **2026-10-23 18:24:57** 最终包上传成功，Xcode 返回 `Uploaded package is processing`、`Upload succeeded` 与 `EXPORT SUCCEEDED`。网页已确认构建 7 **正在测试**，关联现有内部与外部两个 `d5` 群组，简体中文测试说明已保存，保留自动通知。外测链接：https://testflight.apple.com/join/tbMC57cD 。
- 包含聊天发送/流式去重/性能、侧栏与思考折叠、移动生图布局、iOS Portal 与系统权限/HealthKit。发布前全量改动 Review 及修复详见 [发布 Review](RELEASE-REVIEW-2026-10-23.md)。
- Swift Core 82 项、Android 81 项及 Lint、iOS 39 项状态/原生测试、13 项界面测试全部通过。Android 最新 APK：`android/app/build/outputs/apk/debug/app-debug.apk`。
- 最终 Release 归档：`artifacts/testflight/Being-0.1.0-7-20261023-final.xcarchive`；App Store IPA：`artifacts/testflight/ipa-0.1.0-7-20261023-final/Town.ipa`。签名、源码一致性与 dSYM 校验通过，最低 iOS 16.0，可执行文件 UUID 为 `EBC7C366-86BF-3DC7-92D4-6E91623214D5`。
- 同一归档开发签名 IPA：`artifacts/testflight/device-0.1.0-7-20261023-final/Town.ipa`；18:24 覆盖安装，18:25 成功启动到 iPhone 16 Pro Max。未清除账号和历史；真机未运行模拟器 fixture 或读取用户健康数据。
- 首次上传因缺少 `NSHealthUpdateUsageDescription` 被 Apple 校验 90683 拒绝；已补齐只读、不请求写入的准确说明。最终产物带 `-final` 后缀，之前本地产物不用于分发。
- 上传日志、源码清单、校验结果：`artifacts/testflight/upload-0.1.0-7-20261023-final.log`、`source-sha256-0.1.0-7-20261023-final.json`、`verification-0.1.0-7-20261023-final.json`。

## 此前构建：0.1.0 (6)

提交前 Review 随后修复了智能 UI 开关的场景恢复及大写围栏历史识别；这两处源码修复尚未重新出包，不包含在下述构建 6 中。回归结果见 `TESTING.md` 顶部。

- **2026-10-21 17:33:22** 上传成功，Xcode 返回 `Uploaded package is processing`、`Upload succeeded` 与 `EXPORT SUCCEEDED`，退出码 0。传输期间出现一次网络连接中断，自动重试后成功。
- 已通过 Chrome 保存简体中文测试说明，向现有外部 `d5` 群组提交 Beta 审核。最终页面显示 **0.1.0 (6) 正在测试**，关联内部和外部两个 `d5` 群组，保留自动通知。外测链接：https://testflight.apple.com/join/tbMC57cD 。
- 包含图片缩放、原图保存与桌面智能界面兼容，回归记录见 `TESTING.md`。Xcode Debug 构建此前已覆盖安装到用户 iPhone 16 Pro Max，设备确认 0.1.0 (6)，安装与启动成功。
- 本地最终归档：`artifacts/testflight/Being-0.1.0-6-20261021-final.xcarchive`；IPA：`artifacts/testflight/ipa-0.1.0-6-20261021-final/Town.ipa`。签名校验通过，二进制与 dSYM UUID 均为 `1DC3D543-0B8A-35A2-BCB8-A3911C977F77`，最低系统 iOS 16.0。
- 用户此前要求暂停上传并先装真机，原上传进程退出 143；随后明确要求提交 TestFlight。恢复前 Chrome 确认 Apple 构建及上传记录均无构建 6，因此重新上传同一份已验证归档。
- 成功上传日志：`artifacts/testflight/upload-0.1.0-6-20261021-resumed.log`；网页凭证：`artifacts/testflight/submitted-0.1.0-6-20261021.png`。源码清单、校验结果及已保存的测试说明分别为同目录下的 `source-sha256-0.1.0-6-20261021.json`、`verification-0.1.0-6-20261021.json`、`what-to-test-0.1.0-6-zh.txt`。

## 此前构建：0.1.0 (5)

- **2026-10-21 16:01:21** 上传成功，Xcode 返回 `Uploaded package is processing`、`Upload succeeded` 与 `EXPORT SUCCEEDED`。
- 修复对话正文中的 Markdown 图片展示，支持流式回复、历史刷新、签名参数、重定向、失败重试与点击预览；修复侧栏关闭后透明遮罩阻挡主界面点击。
- Swift Core 59 项、iOS 26.5 两项 UI 回归通过，截图已复核。iOS 16.4 本轮 runner 在系统 dylib 加载阶段卡住，未完成图片 UI 回归。详细验证范围见 `TESTING.md`。
- Release 最终归档与签名验证通过；最低系统 iOS 16.0，二进制与 dSYM UUID 均为 `0BE24A60-D6E6-35DF-88F1-ABD22BA7756D`。
- 最终归档：`artifacts/testflight/Being-0.1.0-5-20261021-final.xcarchive`；本地 IPA：`artifacts/testflight/ipa-0.1.0-5-20261021-final/Town.ipa`。带 `final` 的产物包含侧栏遮罩修复；先前同版本本地归档未上传。
- 上传日志：`artifacts/testflight/upload-0.1.0-5-20261021.log`；源码清单：`artifacts/testflight/source-sha256-0.1.0-5-20261021.json`；测试说明：`artifacts/testflight/what-to-test-0.1.0-5-zh.txt`。
- 已通过 Chrome 保存简体中文测试说明，并向现有外部 `d5` 群组提交 Beta 审核。网页最终显示构建 5 **已批准**，关联内部和外部两个 `d5` 群组。截图：`artifacts/testflight/approved-0.1.0-5-20261021.png`。

## 此前构建：0.1.0 (4)

- **2026-10-21 15:29:36** 上传成功，Xcode 返回 `Uploaded package is processing`、`Upload succeeded` 与 `EXPORT SUCCEEDED`。
- 包含篝火、围炉、私信、设置页布局调整，公告与筛选导航修复，以及侧栏关闭残影和搜索焦点修复；未接入 Android Portal。
- Release 归档与签名验证通过；版本为 `0.1.0 (4)`，最低系统 iOS 16.0，二进制与 dSYM UUID 一致，包含隐私声明，不含 XCTest。此前 UI 回归及真机安装记录见 `TESTING.md`。
- 上传归档：`artifacts/testflight/Being-0.1.0-4-20261021.xcarchive`；上传日志：`artifacts/testflight/upload-0.1.0-4-20261021.log`；源码清单：`artifacts/testflight/source-sha256-0.1.0-4-20261021.json`。
- 已通过 Chrome 保存简体中文测试说明并向现有外部 `d5` 群组提交 Beta 审核。网页最终显示构建 4 **已批准**，关联内部和外部 `d5` 两个群组；未新增测试员或修改公开链接。截图：`artifacts/testflight/approved-0.1.0-4-20261021.png`。
- 本地 App Store IPA：`artifacts/testflight/ipa-0.1.0-4-20261021/Town.ipa`。已知 Markdown 图片语法尚未实现图片展示，已写入测试说明；图片附件仍可预览。

## 此前构建：0.1.0 (3)

- **2026-10-20 15:00:04** 上传成功：Xcode 日志明确返回 `Uploaded package is processing`、`Upload succeeded`、`Uploaded Town`、`EXPORT SUCCEEDED`，退出码 0。
- 包含本次对话流、实时正文与思考过程、历史确认后过程更新、输入框聚焦定位、输入栏间距及相机全屏修复。最低系统仍为 **iOS 16.0**。
- 发布前已通过 Swift Core 55 项、iOS 16.4 状态测试 11 项，以及 iOS 16.4 / 26.5 相关 UI 回归。最后的历史确认分支另通过 iOS 16 状态回归及 iOS 26 完整分段/过程 UI 回归，详见 [对话流报告](CHAT-FLOW-REVIEW-2026-10-20.md)。本次仅递增构建号，不重复运行已通过的测试。
- Release 归档、签名验证通过；Info.plist 与 Mach-O 均确认最低系统 16.0；二进制和 dSYM 的 arm64 UUID 一致，隐私声明存在，未包含 XCTest 测试包。
- Apple 已开始处理，最终处理完成和测试群组分发状态尚未确认。本次未修改群组、成员或分配，不代表外部测试审核已通过。
- 本次未创建新的 Git 提交；归档来自当前工作区，源文件 SHA-256 清单保留用于追溯。

本地产物：

- `artifacts/testflight/Being-0.1.0-3-20261020.xcarchive`
- `artifacts/testflight/archive-0.1.0-3-20261020.log`
- `artifacts/testflight/upload-0.1.0-3-20261020.log`
- `artifacts/testflight/source-sha256-0.1.0-3-20261020.json`
- `artifacts/testflight/what-to-test-0.1.0-3-zh.txt`（本地测试说明，未填入网页）

## 此前构建：0.1.0 (2)

- App Store Connect：Being Town，Apple ID `6824474843`。
- Bundle ID：`town.beings.nativeapp`。
- 版本：`0.1.0`；构建号：`2`；最低系统：**iOS 16.0**。
- 归档内 Info.plist 的 `MinimumOSVersion` 和 Mach-O 的 `minos` 均验证为 16.0；Debug、Release 构建号均递增为 2。
- 适配代码的 Swift Core 测试 42 项通过；iOS 16.4 和 iOS 26.5 各 7 项状态测试、4 项 UI 测试通过，另通过 iOS 16.4 深色聊天补测。本次仅递增构建号，重新归档并验证签名，未重复运行完整回归。详见 [兼容性报告](IOS16-COMPATIBILITY-2026-10-20.md)。
- Release 真机归档成功；签名完整性检查通过；归档包含隐私 API 声明和 dSYM。
- 已补充 UserDefaults 使用原因 CA92.1、系统加密豁免配置、iPhone/iPad 方向声明；应用图标移除了无实际透明像素的 alpha 通道。
- 二进制和 dSYM 的 arm64 UUID 一致；归档不包含 XCTest 测试包。
- **2026-10-20 11:54:03**，构建 2 的上传日志返回 `Upload succeeded`、`Uploaded Town` 和 `EXPORT SUCCEEDED`（命令退出码 0）；Apple 已开始处理包。
- 旧构建 `0.1.0 (1)` 于同日 11:07:40 上传，仍要求 iOS 26.0。旧归档和日志保留供追溯。

### 构建 2 的分发核验记录

本轮网页检查停留在 Apple 账户登录页，未能确认 Apple 最终处理结果。Xcode 已使用现有账户成功上传。未修改测试群组、成员或构建分配；上传成功不代表测试者已经可以安装。

在 App Store Connect 的 TestFlight 页面确认 **0.1.0 (2)** 处理完成，并确认所需测试群组已包含该构建。外部测试的分发状态需另行确认。

### 构建 2 本地产物

- 归档：`artifacts/testflight/Being-0.1.0-2-20261020.xcarchive`
- 构建日志：`artifacts/testflight/archive-0.1.0-2-20261020.log`
- 上传日志：`artifacts/testflight/upload-0.1.0-2-20261020.log`
- 测试日志和结果：`artifacts/ios16-compat/`
- 导出配置：`artifacts/testflight/ExportOptions.plist`
- 测试说明草稿（已更新为 iOS 16，尚未填入网页）：`artifacts/testflight/what-to-test-zh.txt`

## 验证边界

本次完成自动化回归、正式构建、签名检查和上传，没有重新执行完整真机功能验收。此前记录的 Ogg Vorbis/Opus 本地播放兼容性问题仍在；后台 APNs 推送尚未实现。已有手动验收详见 `IOS-MANUAL-REVIEW-2026-10-19.md`。
