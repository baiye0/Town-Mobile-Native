# iOS 本机 Portal

入口：**更多 → 本机 Portal**。先连接 Being，再启动 Portal。原生 Swift 实现复用 Android
的 Hearth 出站 WebSocket / MCP 协议，不额外监听端口，不需要 Rust、Shell 或下载运行时。

## 已实现

| 功能 | 行为 |
| --- | --- |
| Relay | 从连接地址推导 `wss://host/_relay`，握手发送 `being_id`、`loom_token`、`portal_name`；使用系统 TLS 校验，不把凭据放入 URL、日志或界面 |
| MCP | `initialize`、`ping`、`tools/list`、`tools/call`；授权变化发送 `notifications/tools/list_changed` |
| 状态 | `portal_status`、`portal_ios_capabilities` 分别报告连接、实际工具、Being 授权与系统权限 |
| 文件 | `portal_file_list/read/write/edit`；UTF-8 读取、UTF-8/base64 写入、追加、唯一文本替换、目录浏览、系统文件导入导出 |
| 搜索 | `portal_search`：大小写不敏感的**字面文本**搜索，非 Android 的正则语法；最多扫描 2000 个目录项、20 MB 文件内容，返回最多 200 条 |
| 日历 | `portal_ios_calendar`：列日历、按时间范围/标题查询、读取、新建、修改、删除；支持全天。重复日程和有参与者的日程不修改，避免影响整个系列或发送邀请 |
| 提醒 | `portal_ios_reminders`：使用系统 EventKit 提醒事项，列清单、查询、读取、新建、修改、完成、删除；设置到期时间时附加系统提醒。重复提醒不修改 |
| 通讯录 | `portal_ios_contacts`：姓名/电话/邮箱查询、新建、修改、删除；支持 iOS 18 的部分联系人授权。修改只替换提供的字段，电话/邮箱数组完整替换 |
| 定位 | `portal_ios_location`：前台单次定位，15 秒超时，返回时间、精度以及是否大致位置，不申请后台定位 |
| 健康 | `portal_ios_health`：HealthKit 活动、睡眠、锻炼、心肺和身体指标共 26 类；只读、由系统选择共享范围，默认最近 7 天，最多 31 天 / 200 条样本，20 秒超时 |
| 确认与记录 | `portal_ios_actions` 按 `request_id` 查询状态；手机显示当前记录和请求内容供用户确认；`portal_ios_activity` 返回最近 100 条工具名、状态、时间，不保留调用参数 |

原生能力默认关闭，读取和请求写入分别授权。开关不等于系统授权；日历和提醒读取在
系统层需要完整访问，Being 的写权限仍单独控制。iOS 16 使用旧 EventKit 授权 API，
iOS 17 起使用完整访问 API。首次请求等待系统结果后才开启 Being 开关，拒绝后保持关闭；已拒绝权限显示系统设置入口。
返回前台或重新加载时移除失效的旧授权，并取消相应待确认写操作。定位等待授权回调，不把请求发出当作成功。

## Apple 健康关联

在 Portal 点击 **关联 Apple 健康**，展示健康关联说明卡片；点击 **继续** 唤起系统 HealthKit 数据共享选择页，点击 **取消** 不建立关联。
由系统页统一选择 26 类活动、睡眠、心肺和身体指标的读取范围，不再设置逐类授权按钮或 Portal 开关。
关联绑定到当前 Being，点击 **断开 Apple 健康关联** 立即停止该 Being 的后续健康查询。

`requestAuthorization` 成功只表示系统流程完成，不证明读取已获准。HealthKit 不公开读取拒绝状态，
因此界面明确区分“已关联当前 Being”与系统读取范围，MCP 报告 `read_authorization: not_disclosed`。
空结果可能是未共享、没有记录或授权时间窗口限制，不解释成零值或已拒绝。

- 活动：步数、步行/跑步距离、骑行距离、游泳距离、爬楼层数、活动能量、静息能量、锻炼时间、站立时间、锻炼记录。
- 心肺：心率、静息心率、HRV、血氧、呼吸频率、VO₂ max、收缩压、舒张压。
- 身体与睡眠：身高、体重、BMI、体脂率、去脂体重、腰围、体温、睡眠。
- 系统只返回用户实际共享的数据。新增类别需用户通过“管理健康关联与共享范围”完成系统选择；旧类别不会自动扩大访问。
- `category` 必填；`start`、`end` 可选，均为含时区的 ISO 8601 时间。不传时间默认最近 7 天；最多 31 天。累计活动指标使用 HealthKit 统计查询、UTC 日期桶，仅包含请求范围内完整样本。
  其他类别返回最新 200 条，超量标记 `truncated`。体重统一 kg、心率 count/min；睡眠保留阶段和来源，不能直接累加重叠来源。
- 不申请写入、临床病历、后台交付，不在 Portal 文件/活动日志缓存健康结果。查询结果通过现有 Being 连接交给远端。
- 断开后丢弃尚未完成的查询结果，但不会删除 Being 已收到的数据。重新关联也不会恢复旧查询结果。
- 部分类别可能受设备或系统限制。当前 iOS 26.5 模拟器的血压两项未出现在共享选择页，查询返回 HealthKit 错误 5；其他 24 类实际查询已验证。此限制不推断为真机同样不可用。
- 再次关联不保证再次弹窗。更改已处理的共享范围需在健康 App 的个人头像 → App → Being 中进行。
- Debug/Release 配置 HealthKit entitlement 和 `NSHealthShareUsageDescription`，设备签名需要支持 HealthKit 的 provisioning profile。

### MCP 调用契约（0.2.0-ios）

```json
{"name":"portal_ios_health","arguments":{"category":"sleep"}}
```

上例查询最近 7 天睡眠。指定范围示例：

```json
{"name":"portal_ios_health","arguments":{"category":"steps","start":"2026-10-20T00:00:00+08:00","end":"2026-10-23T00:00:00+08:00"}}
```

`portal_ios_capabilities` 的 `health` 字段返回当前类别的 `category` 标识、中文名、单位、聚合方式、
`input_schema`、`query_example`、默认/最大天数。参数错误列出缺失字段、不支持的字段、允许字段与示例，
枚举错误列出可选值，避免 Being 猜测字段。HealthKit 系统失败返回错误码和下一步指引，与参数错误区分。
升级后重新启动 Portal，让远端重新加载 `tools/list`；远端旧缓存不能作为新接口契约。

## 写入确认与重试

系统日历、提醒和联系人每次写入都要求 `request_id`。首次调用返回 `pending`，
此时尚未修改系统数据。用户在 Portal 中核对完整内容并确认后才执行；Being 使用
`portal_ios_actions` 查询最终状态，不应把排队当作完成，也不应换 ID 绕过确认。

相同 ID、相同参数返回已有状态；同 ID 不同参数拒绝。最多保留 400 条请求，20 条待确认。
关闭对应写授权会取消待确认请求。确认时再次检查权限、记录内容和 24 小时有效期；
目标记录已变化时标记 `stale`，需重新读取后提交。执行前持久化 `executing`，
崩溃恢复后标记 `unknown`，不会静默重做；系统 Provider 与本地日志并非跨库原子事务。
拒绝为 `rejected`，撤销授权为 `cancelled`，过期为 `expired`，完成为 `completed`。

示例：开启日历读取和请求写入并完成系统授权后，请 Being 查询明天的空闲时间并提交
一条日程；在手机 Portal 的“待确认操作”中核对后执行。联系人、提醒事项同理。

## 隔离与限制

- 配置、请求记录、文件按连接 endpoint 的 SHA-256 隔离，位于
  `Application Support/ios-portal/<owner>/`，排除备份并使用系统文件保护。
  凭据继续使用既有 Keychain，不复制到 Portal 文件。
- 文件工具只能操作 `workspace/`；拒绝绝对路径、`..`、所有符号链接组件（包括悬空链接）。
  文件导入不覆盖同名文件。单文件最大 10 MB；WebSocket 请求/响应各最大 1 MB，
  文本读取结果最大 160000 字符，因此较大文件需分段读写或通过系统文件选择器导入。
- 停止、切换/更新 Being 连接立即取消 socket 与挂起调用；旧响应不能进入新会话。
  已完成的系统修改和工作区文件保留，不因切换身份而删除。
- 前台运行；进入后台暂停，回到前台恢复同一 Being。重启 App 后需要手动启动。
  **不宣称 iOS 后台常驻**，也不使用静音音频、定位或其他无关后台模式保活。
- 15 秒心跳、90 秒存活期限；协商 `text-v1`，否则使用 WebSocket ping；
  握手最多 20 秒，心跳写入最多 10 秒。断线以 2–30 秒指数退避加抖动重连，
  明确握手拒绝则停止重试。最多 4 个在途 MCP 请求。
- 当前不发布 Shell/进程、网页抓取、系统闹钟交接、分享扩展、其他应用通知读取/回复、
  地点提醒、屏幕控制、Kit、自定义 MCP、子代理工具。Android 和 iOS 并非完整能力对等。
  文件导入导出是系统文件选择器，不等同于系统 Share Extension。
- 未使用真实 Being 凭据验证公网端到端；原生正向测试仅在隔离模拟器中使用合成记录。
  真机权限拒绝、部分联系人、真实定位、账号同步和系统通知交付仍需真机验收。

## 参考与实现依据

- 本仓 Android Portal 协议与分层授权：[Android Portal](ANDROID-PORTAL.md)。
  Relay 参考固定的 [heart-portal relay_client.rs](https://github.com/d5z/heart-portal/blob/5cf3acb005e06d990a4157dd83a18b9ba4857554/portal/src/relay_client.rs)。
- [nanoMuse](https://github.com/nano-muse/nanoMuse) 的
  [iOS 原生能力](https://github.com/nano-muse/nanoMuse/tree/bfbe5edf67e2804802faccfdaad7c85c49694a79/android/src/ios/NativeOffloads)、
  [原生权限管理](https://github.com/nano-muse/nanoMuse/blob/bfbe5edf67e2804802faccfdaad7c85c49694a79/android/src/ios/Agent/Offload/OffloadPermissionManager.swift)
  和 [iOS 说明](https://github.com/nano-muse/nanoMuse/blob/bfbe5edf67e2804802faccfdaad7c85c49694a79/docs/ios.md)。
  参考能力划分、系统 API 和操作确认思路，未引入其 GPL 源文件、iSH 或后台保活实现；
  本实现独立编写并适配 Being 的 MCP relay。
- [ChatGPT 官方移动端说明](https://developers.openai.com/training/walkthroughs/working-on-your-phone)：
  参考连接工具前检查权限与由用户审批的交互原则，不宣称复制其 Health 产品界面。
- [nanoMuse HealthKit offload](https://github.com/nano-muse/nanoMuse/blob/bfbe5edf67e2804802faccfdaad7c85c49694a79/android/src/ios/NativeOffloads/HealthKitOffload.m)：参考健康类别与原生查询边界，独立实现 Swift 只读工具。
- Apple：[HealthKit 读取授权与隐私](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)、[EventKit 授权](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)、
  [后台执行时间](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time)。

## 开发验证

纯逻辑、边界与跨端协议测试：`swift test`。
Xcode scheme `Town` 包含 `IOSPortalTests` 和 `PortalUITests`；真实 loopback WebSocket 测试不依赖后端。
原生正向测试要求**独立模拟器**已授予 calendar、contacts、reminders、location 权限；
未授权时跳过对应正向测试，默认不会在测试中弹窗申请。定位测试使用模拟坐标
`31.2304,121.4737`。请勿在含个人数据的设备运行原生写入 QA。

```sh
xcodebuild -project ios/Town.xcodeproj -scheme Town -configuration Debug \
  -destination 'platform=iOS Simulator,id=<isolated-simulator-id>' \
  -derivedDataPath artifacts/PortalDerivedData CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  -only-testing:TownTests/IOSPortalTests -only-testing:TownUITests/PortalUITests test
```

原生测试创建唯一命名的合成事件、提醒和联系人，校验确认、去重、撤权和删除，并清理记录。
授予模拟器权限不替代真实用户授权流程验证。具体本轮结果见 [TESTING.md](../TESTING.md)。

### 健康关联请求结果

“继续”会等待 HealthKit 请求结束，不再自动关闭说明页。流程完成后保留结果与健康 App 内修改共享范围的路径，由用户点“完成”关闭；失败留在原页显示提示，可再次尝试。只有系统流程完成且本地关联配置保存成功才显示完成状态。

同一批健康类型已选择过时，iOS 可以直接返回而不重复展示系统选择页。完成回调、关联状态均不能证明读取权限已获准；不使用写入权限状态或空查询结果推断读取授权。
