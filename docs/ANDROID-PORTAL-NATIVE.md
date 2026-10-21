# Android Portal：前两批原生能力

入口：**更多 → 本机 Portal → 手机原生能力 → 展开授权设置**。
所有原生能力默认关闭。开启当前 Being 的读/写开关时，会自动申请缺少的 Android 系统权限，或引导进入对应特殊权限设置。
每项分别显示 **Being 授权** 与 **系统实际状态**。开关打开不代表系统已授权；拒绝后保留使用意愿，但显示“待系统授权”，工具仍会拒绝访问。点击“继续系统授权”可以重试；系统不再弹窗时进入应用设置，返回后自动核实权限。
读取日历/通讯录只申请读权限；写入按实际操作需要申请读写权限。地点提醒依次引导精确位置、始终允许位置、通知。大致位置、部分健康数据授权、通知访问已授权但服务未连接、定位关闭和 Google Play 服务不可用均单独显示。
关闭 Being 开关立即阻止该项新调用，不自动撤销 Android 系统权限；可通过“打开系统应用权限设置”撤销。Health Connect 状态来自实际授权类别查询。
`portal_android_capabilities` 中 `grants` 保留为 Being 策略，新字段 `system_access` 独立返回每项读/写的系统状态（`required`/`partial`/`granted`/`not_required`/`unavailable`/`unknown`）与限制说明，避免将开关误认为系统授权。
首次开启后重启 Portal 刷新工具列表。关闭立即拒绝新调用；已经执行的操作不会自动撤销。

## 已实现范围

| 批次 | 能力 / MCP 工具 | 行为与边界 |
| --- | --- | --- |
| 一 | `portal_android_calendar` | 列出日历、按时间/标题查询、读取、新建、完整替换更新、删除；每天/每周/每月重复、间隔与次数、提前提醒、全天事件。更新和删除作用于整条日程/整个系列，不提供单次重复实例例外编辑。 |
| 一 | `portal_android_contacts` | 姓名/电话/邮箱搜索、本地新建、更新姓名电话邮箱、删除指定 raw contact；保留其他类型信息，不合并或删除其他聚合联系人。 |
| 一 | `portal_android_reminders` | App 自有提醒增删改查；一次/每天/每周，按时区处理夏令时；普通提醒可能延迟，精确提醒需单独系统授权。 |
| 一 | `portal_android_clock` / `phone` | 新建待处理系统闹钟/倒计时/显示闹钟、拨号。手机点击待处理操作后打开系统界面；不自动拨出电话，不把交接当作闹钟保存成功。 |
| 一 | `portal_android_shares` | 接收其他应用 ACTION_SEND / SEND_MULTIPLE 的文字与附件，经用户确认保存；查询、读取、删除收件记录。最多 10 个附件，单文件 10 MB；不自动向 Being 发送对话。 |
| 二 | `portal_android_notifications` | 用户选择应用白名单；读取当前通知、移除通知、使用通知自带 RemoteInput 快捷回复。不是完整聊天记录；回复返回已分发，不能确认对方收到。 |
| 二 | `portal_android_location` | 通过 LocationManager 获取新位置、精度、时间和 provider；15 秒超时。后台使用需后台位置授权。 |
| 二 | `portal_android_geofences` | 创建/替换/查询/删除到达或离开地点提醒及最近事件；100–10000 米半径，单 Being 最多 20 个。依赖 Google Play 服务、精确及后台位置、通知权限；后台触发可能延迟。 |
| 二 | `portal_android_health` | Health Connect 只读步数、睡眠、运动、心率、体重；最多 31 天/次，分页，步数聚合避免重复计数。仅 App 可见时读取，健康记录为空不表示活动为零。 |
| 共用 | `portal_android_capabilities` / `actions` / `activity` | 查看本地授权与设备可用性、待处理操作、最近 100 条执行状态；执行日志不保存参数或健康数据。 |

共 **13 个原生 MCP 工具**。短信、通话记录、任意 App 屏幕操控不在这两批中。

## 使用示例

启用日历读写并完成系统授权后，可对 Being 说：

- “查看明天下午有没有空，并为 15:00 创建一小时的项目讨论，提前 15 分钟提醒。”
- “每天晚上九点提醒我整理当天笔记。”（App 自有提醒，不依赖日历 App。）
- “打开一个 10 分钟倒计时。”（到手机的待处理操作中继续。）
- “把我分享过来的会议安排整理成日程。”
- “总结我允许的应用当前通知。”
- “读取今天的步数和昨晚睡眠。”（需手机打开 Being，且 Health Connect 已有来源数据。）

工具的每次写操作需要唯一 `request_id`。网络超时后使用同一个 ID 和完全相同的参数重试。
本地保留最近 400 个成功写请求；相同 ID 不同参数会被拒绝。这是有限重试去重，
不保证系统 Provider 写入与本地去重记录之间进程崩溃的跨数据库原子性。

## 授权、存储与生命周期

- 本地策略按连接 endpoint 的 SHA-256 隔离，读和写独立；工具参数无法开启授权。
- 分享文字通过分享读取授权访问；附件进入当前 Being 工作区，已有文件读取能力即可读取附件，
  接收确认界面明确告知这一点。删除收件记录不删除附件，可在工作区管理附件。
- 原生记录保存在 `noBackupFilesDir/android-portal/<owner>.json`，文件工作区也按 owner 隔离。
  旧版公共工作区保留在 `noBackupFilesDir/portal/workspace`，不会自动复制到新身份。
- 日历/联系人使用系统 Provider，可能由相应账号同步；授权读取会把结果交给当前 Being 服务。
  健康授权页提供原生数据使用说明和撤销说明。
- 系统 OS 权限与 Being 本地授权必须同时满足。通知访问授权后仍需逐应用白名单。
- 开启 Shell 仍意味着提供 App UID 能力；原生授权与工作区边界不是 Shell 沙箱。
- 提醒独立于 Portal 的运行状态。关闭原生写权限或切换 Being 后，后台 Job 清理注册；
  广播接收端还会重新验证当前 Being 和授权，避免清理前的旧回调产生提醒。
- 开机、升级、精确闹钟权限变更调度 JobScheduler 恢复当前身份已授权的提醒；
  不在广播接收器里等待 Google 服务网络调用，不自动启动 Portal。
- 手机强停、厂商省电、无 Google Play 服务和系统权限撤销会影响后台功能，不报告虚假成功。

## 实现结构

Rust `android_tools.rs` 将原生工具接入现有 MCP/relay；`PortalService` 创建随机端口的
**仅 loopback** bridge，通过进程环境传递随机鉴权 token。bridge 在校验身份与策略后调用
Kotlin 系统适配器，不经过 Shell。请求上限 256 KB、响应 1 MB、最多 4 个连接，
未认证读取限时 2 秒，Rust 调用总超时 25 秒。退出服务关闭 bridge；Shell 环境剔除 bridge 凭据。

`AndroidPortalSettings` 管理授权、通知白名单、待处理操作、提醒、分享与执行记录。
`AndroidPortalRestoreJob` 处理后台恢复；`AndroidPortalReminderReceiver` 和
`AndroidPortalGeofenceReceiver` 处理系统回调。

## 构建与验证

构建命令沿用 [Android Portal](ANDROID-PORTAL.md)。独立 QA 包额外测试
原生能力；测试 APK 中有一个受 `android.permission.DUMP` 保护的 SDK-only 通知 fixture，
快捷回复只写该测试 APK 的本地偏好，不向任何人发送消息。

模拟器完整验证前需撤销之前 QA 授予的 `android.permission.health.READ_STEPS`，
以验证未授权拒绝分支。授权操作仅发生在独立 QA 包，不改正式 Being 的系统权限。
测试使用随机合成日历、联系人、提醒和分享；正常退出清理测试数据及 QA 连接。
健康和位置正向查询仅在无个人数据的模拟器中进行。

本轮具体结果、尚未覆盖的场景与产物见 [原生能力 Review](ANDROID-PORTAL-NATIVE-REVIEW-2026-10-21.md)。

## Android 官方依据

- [Calendar Provider](https://developer.android.com/identity/providers/calendar-provider)
- [Contacts Provider](https://developer.android.com/identity/providers/contacts-provider)
- [常用 Intent](https://developer.android.com/guide/components/intents-common)
- [NotificationListenerService](https://developer.android.com/reference/android/service/notification/NotificationListenerService)
- [AlarmManager](https://developer.android.com/develop/background-work/services/alarms)
- [Geofencing](https://developer.android.com/develop/sensors-and-location/location/geofencing)
- [Health Connect 读取数据](https://developer.android.com/health-and-fitness/health-connect/read-data)
