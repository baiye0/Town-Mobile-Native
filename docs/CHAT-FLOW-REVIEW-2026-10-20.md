# iOS 对话流、输入栏与相机修复

参考 Town-Client `9268a40` 的 `desktop/renderer/chat/services/runtime.ts`、`models/reply-bubbles.ts`、`components/composer.tsx`、`hooks/use-message-scroll.ts` 及对应聊天测试。最低系统保持 iOS 16.0。

## Review 结论与修改

| 用户可见问题 | 原因与修复 |
| --- | --- |
| 已经收到回复，提问仍显示“正在发送” | 发送队列条目持续到整个回复结束，气泡直接展示队列阶段。普通发送改为即时回显，等待回复由回复区表示；排队、附件准备、失败及结果不确定仍显示可操作状态。 |
| 回复先跑到提问上方，再跳回下方 | 历史先确认提问的服务端序号，未确认的回复仍按旧 baseline 排序。新增提问/前序消息锚点；历史确认保留本地身份，不因序号到达时间改变相对顺序。 |
| 连续回复合成一大段或提前结束 | 明确区分单条回复结束与整个流结束。`message_stop` 关闭本条回复，后续文本创建新回复；持久化元数据绑定序号，重连继续保留气泡身份。 |
| 输入和流式更新卡顿 | 草稿移至独立 `ComposerState`；输入不广播整个 Store。SSE 字节解析离开主线程，界面最多每 50 ms 合并一次流式更新，结束/取消时刷新尾帧。周期队列快照在串行后台写入，关键发送/停止/删除仍按顺序落盘；Markdown 行内结果和图片缩略图有界缓存。 |
| 长回复追着尾部滚动 | 回复占满视口后保留开头阅读位置；用户手动滚动优先，新提交和显式“回到底部”恢复跟随。 |
| 生成时只能停止，无法继续输入发送 | 保留键盘和草稿；同场景可立即发送或明确加入队列。优先条目先持久化排序再停止旧流，避免旧流退出时先发送普通排队条目。 |
| 相机上下白边、整个页面未全屏 | 从对话根视图展示全屏相机，先关闭资源库 sheet；黑色容器覆盖安全区，系统相机管理自身控件布局。 |
| 输入文字离加号太远 | 移除输入框额外的 18 pt 左侧内边距，保留控件间统一间距。 |

补充审查修复：重复正文逐条匹配而非复用同一气泡 ID；历史回执不能冻结或截短仍在增长的正文；停止操作精确关联当前发送条目；删除本地提问清理其多条未确认回复；恢复等待按有效进展计算空闲超时，空元数据与其他场景事件不能无限延长等待。

## 验证

- Swift Core：53 项通过，包括消息顺序、重复回复、持久化身份、回复边界、可见状态、空闲进展判断及异步快照不覆盖后续关键提交。
- iOS 16.4 / iPhone 14：10 项状态测试、8 项 UI 测试通过。最后的身份合并审查修改另跑状态回归。
- iOS 26.5 / iPhone 17：最终完整回归通过，10 项状态测试、8 项 UI 测试，0 失败。
- iPhoneOS Release：最终构建通过，Info.plist 与 Mach-O 最低系统均为 16.0。仅保留无 AppIntents 依赖的构建提示。

UI 使用本地 loopback 合成服务，走正式应用的连接、历史、POST 与 SSE 路径。覆盖：

1. 相机全屏边界、取消、再次打开。
2. 输入草稿在侧栏和标签切换后保留。
3. 历史先确认提问，回复仍在提问下方；普通提问无“正在发送”。
4. 流式期间继续输入，草稿保留；一轮内两条回复顺序与身份稳定。
5. 长回复继续增长时保留开头阅读位置。
6. 服务端记录的请求顺序为“当前消息 → 优先消息 → 排队消息”。
7. 历史 60→61 条刷新不抢走阅读位置，回到底部可用。
8. 欢迎、连接与未连接空状态导航。

首轮 UI 自动化有连接弹窗尚未关闭就输入，以及键盘遮住标签栏时清理测试连接的时序失败；测试已等待弹窗/键盘完成关闭并在清理前收起键盘。曾有 iOS 26 测试 runner 意外退出，后续使用独立 QA 设备串行复测，不将失败运行计为通过。

本地证据：`/tmp/Town-chat-reviewed16.xcresult`、`/tmp/Town-chat-final-state16.xcresult`、`/tmp/Town-chat-final26.xcresult`；截图在忽略目录 `artifacts/chat-flow/`。测试日志和设备产物不进入 Git。

## 验证边界与发布状态

- 本轮为 iOS 修复；未修改 Town-Client 或 Android。
- “立即发送”在原生端使用已确认的 `/api/stop` 后发送优先消息；Town-Client 的同流 splice 传输没有在本轮照搬，不能将两者描述为相同的服务端执行方式。
- 相机全屏及取消流程在模拟器验证，真实传感器拍摄、中文输入法长时间输入与真机性能仍需设备验收；没有给出实测 FPS 或帧耗时结论。
- 测试未使用真实账号发送消息、上传照片或修改服务端配置。
- 本轮修复尚未重新提交、打包上传。已上传的 TestFlight `0.1.0 (2)` 是本轮修复之前的版本。

复现核心测试：`swift test`。设备测试使用共享 `Town` scheme，关闭并行 UI 测试，模拟器签名采用 `CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES`；完整测试运行 `test`，仅状态测试加 `-only-testing:TownTests`。

## 后续：聚焦输入框回到底部

按用户后续要求，输入框获得焦点时退出历史阅读/长回复开头锚定，立即回到最新消息。键盘完成展开、输入框变成多行导致可视高度变化时再次对齐底部；不监听每个输入字符，不恢复整段历史的按键重绘。输入期间主动拖动历史仍优先，只有再次获得输入焦点才重新回到底部。

iOS 16 首轮回归复现了仅靠焦点和布局变化滚动仍停在倒数几条消息的情况，补充 `keyboardDidShowNotification` 后，最新消息保持在键盘和多行输入栏上方。测试为消息列表添加明确的 accessibility identifier，避免多行输入框自身的滚动视图被误选为历史列表；拖拽限定在导航栏下方、输入栏上方的可见区域，避免 iOS 26 的 accessibility frame 延伸到导航栏后方导致手势没有作用于消息列表。

iOS 16.4 新增焦点/多行输入/再次聚焦 UI 用例通过（`/tmp/Town-composer-focus16-final.xcresult`）；历史阅读和长回复锚定回归分别在 `/tmp/Town-composer-focus16.xcresult` 中通过。iOS 26.5 新增用例在 `/tmp/Town-composer-focus26-verified.xcresult` 中通过，另外两项回归在 `/tmp/Town-composer-focus26.xcresult` 中通过。两套系统各覆盖三项相关 UI 回归；本次未重跑其余无关套件。截图：`artifacts/chat-focus/ios16/`、`artifacts/chat-focus/ios26/`。一次 iOS 26 复测遇到测试 runner 启动失败（Mach -308），等待测试进程退出并重启专用模拟器后完成验证。

本项仍未上传 TestFlight。微信未查到明确说明该焦点细节的官方资料，因此本项按用户指定交互实现，不宣称已经验证所有微信版本的行为。

## 真机安装（2026-10-20 14:28，Asia/Shanghai）

按用户要求，通过 Xcode 工具链完成当前工作区 Debug 真机签名构建，并使用 `devicectl device install app` 覆盖安装到连接的 iPhone 16 Pro Max（iOS 27.0），安装成功。未卸载应用或清除数据。构建日志：`/tmp/Town-iPhone-current-build.log`；安装结果：`/tmp/Town-iPhone-current-install.json`。

自动启动被设备锁屏拒绝（Locked）；用户解锁后可打开 Being 体验本轮修改。此安装记录不代表真机交互验收完成，也不改变 TestFlight 发布状态。

## 后续：实时正文与独立过程展示

用户在真机反馈正文整段出现、看不到思考过程后，再次对照 Town-Client `runtime.ts` 的 `consumeChatStream` 与 `messages.tsx` 的 `ChatActivity`，确认上一轮对齐不完整：

- 原生端把过程附在回复气泡上，第一段正文之前没有可展开的过程，只显示圆点。现在将本轮过程保存在发起消息上，独立显示在提问和回复之间；正文到达前提供实时预览和展开入口，结束后自动收起并保留详情。后续历史合并保留该过程，不复制到每个回复气泡。旧版本保存的气泡内过程仍可展开。
- 原生 SSE 对任何非 JSON 的 `data:` 抛错并退出读取，随后走恢复接口；这条路径可能表现为等历史完整落库后整段出现。现在与桌面端一致跳过无法解码的数据帧，继续接收后续合法事件；合法的服务端 `error` 事件仍走错误处理。
- 文本增量按桌面端的 `delta.text` 接收，不再额外限定 `delta.type == text_delta`；同时识别 `delta.thinking`，避免将该进度丢弃。原有 50 ms 合并刷新与结束时 flush 保留。
- 复查独立过程与历史合并的交互，发现用户消息获得服务端序号后，原有保护已确认消息的分支也会阻止过程继续更新。现保留服务端正文与序号，单独更新本地实时过程；状态测试覆盖已确认提问，UI 测试增加思考期间刷新历史。

新增 UI 用例通过真实 URLSession/SSE/SwiftUI 路径测试：先发送非 JSON 心跳，再发送两段 reasoning 和工具调用/结果；正文的下一片段仅在断言上一片段已出现在屏幕后才发送。第三段显示时连接仍未结束，随后才发送结束帧，并检查过程自动折叠、详情保留、顺序和回复唯一性。上一轮用例主要覆盖消息顺序与多气泡边界，不足以单独证明此行为。

当前证据：Swift Core 55 项通过（`/tmp/Town-live-process-core.log`）；iOS 16.4 11 项状态测试与 2 项 UI 测试通过（`/tmp/Town-live-process16.xcresult`）。截图已人工检查，位于 `artifacts/live-process/ios16/`。iPhoneOS 签名 Debug 构建通过（`/tmp/Town-live-process-device-generic.log`），最低系统仍为 16.0。

iOS 26.5 的实时过程/分段正文、消息顺序、长回复阅读、输入框聚焦定位 4 项 UI 回归通过（`/tmp/Town-live-process26.xcresult`）。历史确认后过程继续更新的最后修改，另通过 iOS 16.4 状态回归（`/tmp/Town-live-process16-ack.xcresult`）和 iOS 26.5 含思考期间刷新历史的完整分段 UI 回归（`/tmp/Town-live-process26-ack.xcresult`）。最终真机签名构建通过（`/tmp/Town-live-process-device-final-generic.log`）。截图位于 `artifacts/live-process/ios26/` 和 `ios26-ack/`。

边界：本轮发现并修复可导致退回完整历史的读取错误，但没有抓取用户那次真实服务端的网络事件，不能确认非 JSON 帧就是该次现象的唯一原因。分段显示已在可控服务验证；实际服务若不提供正文增量或 reasoning，客户端不能产生未收到的增量或思考内容。本轮尚未提交或上传 TestFlight。

安装状态：此前设备短暂重连后再次不可用，`devicectl` 安装返回 CoreDevice 1011（找不到设备）。用户随后明确选择“先完成修复，稍后安装”，因此本轮未安装至真机。最终签名应用保留于 `/tmp/Town-iPhone-current/Build/Products/Debug-iphoneos/Town.app`，不可把 14:28 的旧安装记录视为包含本节修复。

后续安装（2026-10-20 14:53，Asia/Shanghai）：用户重新连接手机并要求安装，已将上述最终签名包覆盖安装至 iPhone 16 Pro Max，`devicectl` 确认安装成功，并成功启动 `town.beings.nativeapp`。本次安装包含实时正文、独立思考过程及历史确认后过程继续更新的修复；未卸载或清除应用数据。结果：`/tmp/Town-live-process-reinstall.json`、`/tmp/Town-live-process-reinstall-launch.json`。TestFlight 状态不变。

后续发布（2026-10-20 15:00，Asia/Shanghai）：按用户要求递增为 `0.1.0 (3)` 并完成 Release 归档和上传，Xcode 确认上传成功、Apple 开始处理。最终处理与分发状态尚未确认，详见 [TestFlight 发布记录](TESTFLIGHT-0.1.0.md)。

## 远程提交前复核

再次检查 SSE 接收与结束边界、回复身份/顺序、历史合并、队列停止与优先发送、快照写入顺序、输入状态隔离、滚动和相机展示，未发现新的阻断问题。本次未进一步修改产品代码；逐文件 SHA-256 与已上传 `0.1.0 (3)` 的源码清单一致。

提交前重跑 `swift test`，55 项全部通过（`/tmp/Town-prepush-review-core.log`）；`git diff --check` 通过。沿用本报告中已完成的 iOS 16.4 / 26.5 状态与 UI 回归、Release 归档和真机安装证据，不将本次源码 review 描述为新一轮真机完整验收。归档、截图、设备日志和签名文件保持在 Git 忽略目录中。
