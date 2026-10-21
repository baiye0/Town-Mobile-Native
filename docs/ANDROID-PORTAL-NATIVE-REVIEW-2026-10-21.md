# Android Portal 前两批能力：实现与 Review

## 最终提交前 Review（2026-10-21）

本轮检查 Android 宿主/进程生命周期、固定上游适配、鉴权桥接、按 Being 隔离、系统权限、写操作排队与去重、系统应用交接，以及构建/签名配置。修复如下问题：

1. 桥接 `SO_TIMEOUT` 原为单次读取超时，持续滴流可长期占用线程。现按整个请求计算 2 秒截止时间并分块读取；模拟器验证慢速未认证连接被关闭。
2. 写操作等待同一 Being 的串行锁时，用户可能撤销授权或切换身份。现获得锁后、命中去重缓存前再次检查身份/策略，并在返回结果前复查；回归验证两个场景均不执行排队写入。
3. 已取消/已交接的操作历史积累到 100 条会永久阻塞新增。现满额时仅淘汰已结束历史，保留全部待处理项；回归验证新请求可创建且旧待处理操作保留。

最终验证：65 项 JVM 测试、29 组模拟器端到端场景通过，Lint 0 errors、62 warnings；此前 5 组权限 UI 回归通过。未发现其他阻断本次 Debug 交付的问题；下方真实地理围栏、OEM 后台和非空健康数据边界仍保留。完整 QA 重跑须使用全新安装的模拟器 QA 包，不能沿用上次测试授予的健康权限。

本次输出为 Being 本体包名 `town.beings.nativeapp` 的 Debug 签名 APK，可覆盖同签名安装；不是商店 Release 签名产物。构建完成后生成带主仓提交标识的 APK、SHA-256 和构建元数据，旧产物段落仅表示各次历史构建。

## 系统授权交互补充 Review（2026-10-21）

- 修复开关只写 Being 策略、系统权限状态未展示的问题：开启时申请所需权限，并分别展示策略和 OS 实测状态；拒绝不冒充成功，系统不再弹窗时引导设置，恢复前台重新检查。
- 读取日历/联系人只请求读权限；写操作请求其真实需要的读写权限。后台位置与前台位置分步申请，通知监听、精确提醒、Health Connect 使用各自系统入口；不通过 shell 放开真机权限。
- UI 与 `portal_android_capabilities.system_access` 共用状态规则；写入能力不由只读授权推导；部分健康授权、大致定位、通知监听未连接、定位关闭、GMS 不可用分别标识。原执行路径仍同时检查本地策略与系统权限。
- 65 项 JVM 测试、5 组模拟器 UI 测试通过，Lint 无错误。模拟器测试实际触发并拒绝系统权限框；授予后返回场景使用模拟器 shell 授予权限，再验证 UI 刷新。真机完成本体安装、校验和启动，OEM 限制 ADB 输入，未自动点击真机授权按钮。
- 边界：已授予权限不等于一定存在可写日历、健康记录或可用地理围栏服务。实际 provider 调用仍保留运行时检查；不把系统交接或提醒调度当成最终送达。

## 交付范围

实现 13 个原生 MCP 工具，覆盖系统日历与联系人、自有提醒、时钟/拨号交接、
分享收件箱、通知读取/移除/快捷回复、当前位置/地理围栏、五类 Health Connect
读取，以及权限状态、待处理操作和执行记录。入口和具体边界见
[原生能力说明](ANDROID-PORTAL-NATIVE.md)。

按用户后续要求，Rust 适配直接提交并推送到
[`d5z/heart-portal` 的 `android-portal` 分支，提交 5cf3acb](https://github.com/d5z/heart-portal/commit/5cf3acb005e06d990a4157dd83a18b9ba4857554)。
安卓主仓以 `.gitmodules` 和 `android/portal-runtime/upstream` gitlink 固定引用，
Gradle 直接从子模块构建；不再维护复制的 Rust 源码或补丁层。
主仓的 Android/Kotlin 改动仍为待提交工作区改动。

## 已完成验证

| 检查 | 结果 |
| --- | --- |
| Android 双 ABI | ARM64 / x86_64 Rust + Kotlin APK 构建通过 |
| JVM | 58 项通过，0 失败，涵盖既有功能及新时间范围、重复规则、DST、漏期跳过逻辑 |
| Android Lint | 0 errors，61 warnings；包括既有弃用/依赖升级提示及需要同步持久化的偏好设置提示 |
| Windows Rust 回归 | 323 passed，0 failed，1 ignored；含新增关闭文件/搜索/网页能力后直接调用拒绝测试 |
| Android 16 x86_64 模拟器 | 最终子模块实现通过 26 组端到端场景 |
| Git Review | 主仓与子模块 `diff --check`，子模块提交和远端分支哈希一致 |

模拟器测试通过真实 APK 内的 ELF、前台服务、WebSocket relay、MCP 和原生 bridge：

- 独立 `--version` 不依赖 APK 宿主环境，保留其他 Android 启动器兼容性。
- 随机合成日历中重复事件的创建/展开/更新/读取/删除、15 分钟提醒、重复请求去重与冲突拒绝。
- 系统 Contacts Provider 合成联系人创建/搜索/更新/删除，不读取个人联系人。
- 自有提醒创建/修改/恢复/删除、过期广播不能提前触发新时间；真实 BroadcastReceiver
  发布 NotificationManager 通知并保存投递状态。
- 时钟和拨号请求保持待处理状态，取消后可查询结果，不发起真实电话或保存真实系统闹钟。
- 实际 ACTION_SEND Activity、用户确认按钮、收件记录保存与 MCP 读取/删除。
- NotificationListener 仅允许独立测试 APK；真实 RemoteInput 快捷回复写入该 APK 的本地
  SharedPreferences 并核对返回结果；应用白名单拒绝及通知移除均通过。
- 五类 Health Connect 实际授权查询在无个人数据的模拟器中返回有效结果；未授权请求被拒绝。
- LocationManager 通过测试 provider 返回固定坐标、精度与时间，走完整 MCP 路径。
- 当前模拟器未成功完成地理围栏注册；已验证失败响应及移除未成功注册的本地记录，不能视作成功路径验收。
- 错误 bridge token、关闭的能力、身份切换、跨身份工作区隔离均有验证。
- 既有文件边界、HTTPS、重连、后台回调、超时进程清理、崩溃恢复、受控重启、快速启停继续通过。

日志：`artifacts/android-native-emulator-test.log`、
`artifacts/portal-upstream-host-tests.log`、
`artifacts/android-native-production-build.log`。

## Review 中修复的问题

1. Contacts `Phone.CONTENT_FILTER_URI` 在当前 Android Provider 不支持所需 `raw_contact_id`
   投影；改为参数化 Data Provider 查询并按 raw contact 汇总，也支持无电话的姓名记录。
2. 原生写操作需要服务端实际执行检查，不能只隐藏 tool list；保留按 Being 的读写策略、
   系统权限检查与请求 ID 去重，身份变更后旧 bridge 拒绝新调用。
3. 恢复多个地理围栏可能超过广播接收器时限；改用 JobScheduler，切换身份/关闭授权时
   清理旧注册，回调端再次校验身份与授权。
4. 防止修改后的提醒被旧广播提前触发；重复提醒按 IANA 时区推进，覆盖 DST 和漏期情况。
5. 导入附件的文件访问权限与分享文字权限不同，确认页明确告知；工作区改为按 Being 隔离。
6. 待处理闹钟/拨号返回“待用户处理”，交接后返回“系统结果未确认”；已经交接的操作不能
   通过取消接口伪装成已撤销；处理/取消同时清理待处理通知。
7. 运行时入上游分支时把宿主监管改为显式环境变量启用，避免破坏独立 Android CLI；
   PC 路径保持可用并通过 Windows 回归。
8. 测试通知 receiver 使用独立 test APK 的 SDK-only Java 类，避免依赖目标 APK 中的 Kotlin
   标准库；测试组件不进入生产 APK。

## 后续真机安装补充

2026-10-21 后续应用户要求，已将包含 Portal 的最新正式包名 Debug APK 覆盖安装到 Redmi 本体。
安装后读取设备 APK 的 SHA-256 与最终产物一致；ARM64 内置运行时 `--version` 成功，
本体冷启动及 Portal 页面截图检查通过，现有 Being 连接保留，无 AndroidRuntime 崩溃日志。
临时 QA 应用和测试组件已移除。

本轮真机 QA 的运行时、Relay/MCP 握手通过，但原生 CRUD 测试受运行时权限阻挡：
小米系统拒绝 shell 的 GRANT_RUNTIME_PERMISSIONS。此结果不表示原生功能有代码故障，
也不能计为全量真机回归通过；正式应用系统权限需要用户按功能正常授权。
上述补充取代下方“未安装到正式 Being”的早期状态，其他未覆盖场景仍待验收。

## 验证边界

- Redmi 的 USB/ADB 在本轮传输新版 QA APK 时反复断开；重试流式和推送安装、重启/重连
  ADB 后仍无法稳定安装，**本轮新增原生能力未完成真机验证，也未安装到正式 Being**。
  前一轮 Portal 基础运行时的 11 组 Redmi 实测不是本轮新能力的验证结果。
- 当前模拟器未成功完成实时 Google Play 地理围栏注册，因此成功注册、真实进入/离开地点
  和厂商省电环境下的地点通知仍需支持该服务的真机验证。
- 健康验证使用空的实际 Health Connect Provider，未导入或读取用户真实健康记录；
  有数据情况下的多来源聚合/分页及第三方健康 App 同步仍需验收。
- 提醒通知验证驱动真实 receiver，不代表已做真实墙钟等待、重启手机或 Doze/OEM 长时间测试。
- 系统时钟保存和实际拨出电话未执行；分享文字流程已测，第三方应用附件 URI 行为仍需补充验收。
- 未连接真实 Being 服务发送消息；测试使用本地合成 relay，唯一公网请求为 HTTPS example.com。
- 未执行 macOS 全套回归；已执行 Windows Rust 回归和 Android 双 ABI 构建。

## 产物

- `artifacts/being-portal-debug.apk`：正式包名 Debug APK，可覆盖同签名 Being 安装。
- `artifacts/being-portal-qa.apk`：独立 QA 应用。
- `artifacts/being-portal-qa-tests.apk`：独立 QA instrumentation 与合成通知 fixture。

正式包名 APK 的 SHA-256：
`7727cffab71876e008d09a7acebd66ab68e94ea6793d15a50391df529831ec97`。
APK 签名和 zipalign 校验通过，两个 Portal ELF 的 LOAD 段均为 `0x4000`（16 KB）对齐。
最终 QA 与正式包中的两个 Portal ELF 已核对为逐字节一致，并用该 QA 产物复跑 26 组场景通过。
完整产物大小、ABI 与校验值见 `artifacts/android-native-artifacts.json`。

所有新增能力默认关闭。此轮没有自动授予正式 Being 的系统权限、读取个人日历/健康/通知，
也没有对真实联系人或会话发送消息。
