# 0.1.0（7）发布 Review

日期：2026-10-23。范围为 `codex/native-mobile` 工作区相对 `5802b1f` 的全部已跟踪改动及新增源码；包括聊天、图片、iOS Portal、权限和 HealthKit。未创建 Git 提交。

## 本轮发现并修复

- **已受理消息恢复中断**：点击未知发送状态的重试按钮时，历史已确认但服务器仍在生成，旧逻辑会删除恢复记录。iOS / Android 现在保留 waiting 状态并继续读取原流，不重复 POST；补充核心和端到端回归。
- **Portal 文件查询阻塞界面**：最多 20 MB 的搜索和文件读取原先运行在 MainActor。只读工作移至后台任务，加入搜索取消检查；完成后重新核对连接、会话及文件授权代次，撤权结果不返回。写入继续串行处理。
- **定位状态同步查询**：移除主线程 `locationServicesEnabled()` 同步调用，使用 `authorizationStatus`；SDK 明确规定系统定位关闭也会返回 denied。消除测试中观察到的 UI 无响应诊断来源。
- **测试隔离**：Portal UI 用例仅在确认旧连接为 loopback 测试地址后断开，避免组合运行继承其他 fixture。

- **发布配置补齐**：首次上传被 Apple 校验 90683 拒绝，要求只读 HealthKit 集成也包含 `NSHealthUpdateUsageDescription`。Debug / Release 补充如实说明：本版本不请求健康写入、不写入或修改健康数据。重新归档，18:24:57 上传成功。

## 其余审查重点

- 流式正文按服务端片段更新，首片立即展示，后续短时间合并；结束、错误和取消均冲刷末尾内容。显示缓存仅更新变化项，避免每个包重新合并和排序历史。
- 历史与本地流匹配限定在发起问题所在回合，唯一匹配才合并；检查重复历史、跨问题相同文本和过程消息。
- 未知发送结果不阻塞后续消息；失败按钮在气泡左侧，未知结果先查状态再决定是否发送。
- 生图查询只使用受约束的 HTTPS 端点和对应 Being 身份；图片下载不携带 Being 凭据。成功状态及查询按钮已移除，保留图片加载失败重试和全屏预览。
- Portal 工作区按 Being 隔离，拒绝路径穿越与符号链接；系统写入在授权后直接执行，保留参数指纹及 request_id 去重；中断写入恢复为 unknown。
- 系统授权与 Being 授权分别核对，撤权及切换身份丢弃未完成结果。HealthKit 只读，不把系统流程完成或空结果解释为读取授权成功。

## 验证记录

- Swift Core：82 项通过，`artifacts/release-review-swift.log`。
- Android：81 项单元测试、Lint、Debug APK 构建通过，`artifacts/release-review-android.log`；未修改 Rust Portal，构建复用已有 native 库。
- iOS：39 项 TownTests 全部通过，无跳过；含 12 项状态测试、11 项权限测试、12 项 Portal/原生测试、4 项智能界面测试。最终定位及 HealthKit 查询通过，未再出现主线程定位诊断。日志 `artifacts/release-review-final-native-ios.log`，结果同名 `.xcresult`。
- iOS UI：13 项全部通过，覆盖增量回复、重复回复、长回复滚动、重试及已受理恢复、思考折叠、侧栏/键盘、草稿、图片回执/预览、Portal 启停/权限/健康关联。日志 `artifacts/release-review-retry-ios.log`（同次运行的早期定位偏差已由最终 TownTests 复跑消除）。
- 1000 条历史、100 次正文状态更新最终测量约 280 ms；不包含 SwiftUI 绘制和真实网络，不作为端到端帧率保证。
- Release 归档与 App Store IPA、开发安装 IPA 导出通过；最低 iOS 16.0，构建 7，签名有效，HealthKit entitlement 与隐私声明存在，不含 XCTest。二进制和 dSYM UUID：`EBC7C366-86BF-3DC7-92D4-6E91623214D5`。
- 18:14 首次覆盖安装到 iPhone 16 Pro Max，18:15 成功启动；最终配置修正后 18:24 再次安装，18:25 成功启动；设备查询确认 0.1.0（7），随后查询进程仍在运行。安装包来自同一 Release 归档，仅重新采用开发签名。
- `git diff --check` 通过；归档后重新核对全部 iOS / Android / Tests 源码 SHA-256 一致。
- TestFlight 上传和分发状态见 `TESTFLIGHT-0.1.0.md`。

早期 iOS 运行因模拟器测试启动挂起被中止；重启后组合测试的定位用例收到系统默认坐标而非预设合成坐标，已恢复测试坐标并重跑全部 39 项成功。这些早期失败不计为通过。

## 发布与测试边界

源码 SHA-256 清单、归档、IPA、签名和上传日志保存于 `artifacts/testflight/`。模拟器自动化不代表已对用户的真实 Being、健康记录和全部真机交互完成验收。真实系统写入测试仅在隔离模拟器创建并清理合成数据。

最终归档与产物均使用 `-final` 后缀；源码清单为 `artifacts/testflight/source-sha256-0.1.0-7-20261023-final.json`。首次归档和失败日志保留追溯，不用于分发。最终配置修改未改变可执行代码 UUID，因此未重复已通过的功能回归，重新核验了 Info.plist、签名、版本、dSYM 和手机启动。
