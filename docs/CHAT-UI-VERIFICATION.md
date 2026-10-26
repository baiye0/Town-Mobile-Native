# 聊天图片与发送交互验证（2026-10-23）

## 修复

- 合并远端 `5802b1f` 的移动端图片解析和画廊，补充生图回执流式占位、接收完成后查询、后台暂停及 Android 严格字段类型校验。
- iOS / Android 将发送失败或结果待确认显示为气泡左侧红色感叹号。点击重试；结果待确认先查活动流和历史，已受理消息不重复提交。未确认的旧记录不再阻塞后续发送。
- iOS 思考过程默认折叠，删除折叠状态仍显示的实时预览，显式点击才展示过程。
- iOS 侧栏收起时保留同一图层完成位移，再无动画移除；遮罩不再使用额外退出动画，取消隐藏侧栏的点击响应。重新展开会取消延迟移除。

## 自动化结果

- `swift test`：77 项通过，日志 `artifacts/chat-fixes-final-swift.log`。
- Android `:app:testDebugUnitTest :app:lintDebug -x :portal-runtime:buildPortal`：77 项单测通过，lint 通过，日志 `artifacts/chat-fixes-final-android.log`。未重新构建 Rust Portal。
- iOS 26.5 隔离模拟器：发送失败左侧图标、重试、未确认消息不阻塞、已受理不重发；生图流式卡片和历史恢复；思考默认折叠与增量回复通过。结果 `artifacts/chat-fixes-final-ios.xcresult`（其中较早侧栏实现的两个失败已由后续验证覆盖）。
- Markdown 图片失败重试、全屏预览缩放及历史恢复通过，结果 `artifacts/sidebar-verified-ios.xcresult`（同样含较早侧栏失败记录）。
- 最终侧栏实现：草稿在侧栏及底部导航切换后保留，通过于 `artifacts/sidebar-final-ios.xcresult`；三轮展开、聚焦搜索、收起、键盘关闭及隐藏控件移除通过于 `artifacts/sidebar-repeat-ios.xcresult`。前一次连续开关测试中页面意外切至“更多”，单独复跑同一构建通过。
- 已检查失败气泡及收起侧栏截图，保存在对应 xcresult 附件中。

真实生产生图任务及签名图片下载没有在本轮提交或端到端验证；协议解析与查询限制由单测覆盖。真机安装不会运行 loopback 测试，不清除账号或聊天数据。

## 真机安装

Xcode Debug 构建成功，`town.beings.nativeapp` 版本 0.1.0（6）已于 2026-10-23 17:06 安装到连接的 iPhone 16 Pro Max（iOS 27.0）。构建和安装日志：`artifacts/chat-fixes-device-build.log`、`artifacts/chat-fixes-device-install.log`。未卸载应用或清除数据。

自动启动被手机锁屏拦截（`FBSOpenApplicationErrorDomain: Locked`），因此没有宣称完成真机启动或真实对话验收；解锁后可手动打开。记录：`artifacts/chat-fixes-device-launch.log`。

## 发送转圈与逐段回复补充修复

后续按用户反馈移除 iOS / Android 发送气泡旁的 loading，只保留失败或结果待确认时的红色重试按钮。去掉 50 ms 的文本合并层，完整 SSE 事件解析后立即更新消息。恢复流对齐 Town-Client `runtime.ts`：收到新事件后恢复 500 ms 读取间隔，只有没有事件或网络失败才退避，最多 5 秒。流请求显式声明 SSE，活动流查询禁用缓存。

新增 `testQueuedReplyPublishesReplayFragmentsBeforeCompletion`：模拟 HTTP 202，然后逐段提供活动流事件，每段必须在下一段放出之前显示，完成前不得出现发送转圈。正常 SSE 分段测试同样检查无发送转圈。已移除针对旧 50 ms 合并层的测试，Swift Core 仍为 77 项，Android 为 76 项。

本轮验证：Swift Core 77 项、Android 76 项、Android lint 通过；Xcode 的 10 项状态测试及 3 项界面测试全部通过。日志及结果分别为 `artifacts/incremental-stream-swift.log`、`artifacts/incremental-stream-android-unit.log`、`artifacts/incremental-stream-android.log`、`artifacts/incremental-stream-ios.xcresult`。

17:17 本轮真机 Xcode 构建成功，并再次安装到同一 iPhone 16 Pro Max；17:18 自动启动仍被设备锁屏拒绝。记录：`artifacts/incremental-stream-device-build.log`、`artifacts/incremental-stream-device-install.log`、`artifacts/incremental-stream-device-launch.log`。未清除用户数据。

## 重复回复与对话流性能 review

发现历史接口可以早于 SSE 返回完整回复，旧逻辑只按完整文本匹配，并跳过已缓存的序列号，导致完整历史与流式前缀各占一个气泡。现在 iOS / Android 在发起问题和下一条问题之间匹配唯一回复，绑定原气泡 ID，保留已收到的内容；完成后的同文缓存也可归并。跨轮同文、多个候选均不猜测匹配。

逐包直接发布会反复合并、排序历史并重新解析正文。本轮替代上一节的逐事件发布方式：首包立即显示，密集后续包按 16 ms 合并最新快照，结束、异常及取消前刷新末段。没有人为逐字打字延迟。恢复接口的一批事件只刷新一次，保持 500 ms 活跃轮询。正文增长复用显示顺序，身份、序列、完成状态、历史或可见性变化仍使缓存失效。历史 Markdown 视图使用显式输入比较，固定正则预编译，普通文本跳过附件和生图协议扫描，末条用户消息索引只计算一次。

复现测试在修改前出现两个回复，修改后只保留同一气泡，正文继续增量增长。新增 2,000 片段密集更新和 1,000 条历史场景验证；首次模拟器 Debug 测量连续 100 次模型投影和读取共约 257 ms（约 2.57 ms/次），不包含 SwiftUI 绘制及真机网络，不能作为端到端帧率保证。

首轮验证：Swift Core 80 项通过（`artifacts/stream-review-swift.log`）；Xcode 12 项状态测试与 5 项界面测试通过（`artifacts/stream-review-ios.xcresult`），覆盖历史提前到达、普通 SSE、202 恢复、长回复滚动和图片回执。

## 生图卡片移动布局

iOS / Android 去掉逐张“生成成功”与“重新查询”按钮。图片置于标题上方、使用圆角和更大的预览区域，标题变为最多两行的次级文字；组内统一间距，只在整组显示数量。未完成和异常状态使用简短占位提示，自动轮询及后台暂停仍保留，点击图片进入全屏画廊。图片资源下载失败时保留图片自身的重试入口，避免坏图不可恢复。

最终回归：Swift Core 80 项通过（`artifacts/stream-final-swift.log`）；Android 80 项及 lint 通过（`artifacts/stream-final-android.log`），最后普通文本快速路径修改后再次通过单测（`artifacts/stream-final-android-unit.log`）；Xcode 12 项状态测试和 3 项针对性界面回归全部通过（`artifacts/stream-final-ios.xcresult`）。第二次长历史模型更新测量为 258 ms / 100 次。导出并检查单气泡截图位于 `artifacts/stream-identity-screenshots/`；图片回执截图位于 `artifacts/stream-final-image-screenshots/`。本轮图片界面 fixture 验证回执、连接隔离及无冗余按钮，未使用生产凭据查询真实生图结果。

17:44 Xcode 真机 Debug 构建成功并已安装到连接的 iPhone 16 Pro Max，包含本节对话流及图片布局修改。17:45 自动启动仍被设备锁屏拒绝，尚未进行真机生产对话验收。记录：`artifacts/stream-final-device-build.log`、`artifacts/stream-final-device-install.log`、`artifacts/stream-final-device-launch.log`。未卸载或清除用户数据。
