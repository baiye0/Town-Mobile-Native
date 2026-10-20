# Being Town 0.1.0 TestFlight

日期：2026-10-20（Asia/Shanghai）。

- App Store Connect：Being Town，Apple ID `6824474843`。
- Bundle ID：`town.beings.nativeapp`。
- 最新版本：`0.1.0`；构建号：`2`；最低系统：**iOS 16.0**。
- 归档内 Info.plist 的 `MinimumOSVersion` 和 Mach-O 的 `minos` 均验证为 16.0；Debug、Release 构建号均递增为 2。
- 适配代码的 Swift Core 测试 42 项通过；iOS 16.4 和 iOS 26.5 各 7 项状态测试、4 项 UI 测试通过，另通过 iOS 16.4 深色聊天补测。本次仅递增构建号，重新归档并验证签名，未重复运行完整回归。详见 [兼容性报告](IOS16-COMPATIBILITY-2026-10-20.md)。
- Release 真机归档成功；签名完整性检查通过；归档包含隐私 API 声明和 dSYM。
- 已补充 UserDefaults 使用原因 CA92.1、系统加密豁免配置、iPhone/iPad 方向声明；应用图标移除了无实际透明像素的 alpha 通道。
- 二进制和 dSYM 的 arm64 UUID 一致；归档不包含 XCTest 测试包。
- **2026-10-20 11:54:03**，构建 2 的上传日志返回 `Upload succeeded`、`Uploaded Town` 和 `EXPORT SUCCEEDED`（命令退出码 0）；Apple 已开始处理包。
- 旧构建 `0.1.0 (1)` 于同日 11:07:40 上传，仍要求 iOS 26.0。旧归档和日志保留供追溯。

## 尚未完成

本轮网页检查停留在 Apple 账户登录页，未能确认 Apple 最终处理结果。Xcode 已使用现有账户成功上传。未修改测试群组、成员或构建分配；上传成功不代表测试者已经可以安装。

在 App Store Connect 的 TestFlight 页面确认 **0.1.0 (2)** 处理完成，并确认所需测试群组已包含该构建。外部测试的分发状态需另行确认。

## 本地产物

- 归档：`artifacts/testflight/Being-0.1.0-2-20261020.xcarchive`
- 构建日志：`artifacts/testflight/archive-0.1.0-2-20261020.log`
- 上传日志：`artifacts/testflight/upload-0.1.0-2-20261020.log`
- 测试日志和结果：`artifacts/ios16-compat/`
- 导出配置：`artifacts/testflight/ExportOptions.plist`
- 测试说明草稿（已更新为 iOS 16，尚未填入网页）：`artifacts/testflight/what-to-test-zh.txt`

## 验证边界

本次完成自动化回归、正式构建、签名检查和上传，没有重新执行完整真机功能验收。此前记录的 Ogg Vorbis/Opus 本地播放兼容性问题仍在；后台 APNs 推送尚未实现。已有手动验收详见 `IOS-MANUAL-REVIEW-2026-10-19.md`。
