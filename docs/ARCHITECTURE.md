# 架构

iOS 使用 SwiftUI、URLSession/SSE、Keychain；Android 使用 Compose、OkHttp/SSE、Android Keystore。独立原生项目，无 WebView 产品界面。

## 桌面协议来源

- `desktop/main/chat/connection.ts`、`proxy.ts`：Being 链接、token、relay secret。
- `desktop/shared/town-client.ts`：Town 公开/鉴权接口、收发消息与分页。
- `desktop/shared/town-pairing.ts`：自动配对请求与响应。
- `desktop/renderer/chat/components/being-model-settings.tsx`：模型与思考深度。

对话场景按 endpoint 隔离。删除只作用于本地记录；不调用服务端删除接口。停止生成按 stream_id 发起；消息失败不会自动重发。Town token 与 Being token 分离，实时 hello 验证身份。

自动配对使用独立对话，收集 assistant 文本，等待 message_stop，仅接受唯一的六位配对码。模型修改验证服务端 ok/rolled_back/needs_key，再读取确认配置。

## 页面与视觉

SwiftUI HistoryStack 保存页面路径与前进历史，新导航清除前进历史；左右边缘分别返回/前进。对话根页面左边缘负责侧栏，避免和详情返回冲突。Android 使用 NavigationModel 和局部详情历史，支持边缘手势及系统返回。

iOS 最低支持 16.0（状态管理使用 ObservableObject / @Published，视图使用 StateObject / EnvironmentObject）。iOS 26 的玻璃表面、按钮、工具栏和 GlassEffectContainer 均通过系统版本判断启用，旧系统回退为普通界面；iOS 16–17 使用 tabItem/tag 导航，iOS 18 及以上保留 Tab API。iOS 16–17 的聊天滚动使用内容几何与拖拽状态，iOS 18 及以上使用系统滚动阶段 API。空状态页面、图标按钮、图片预览背景与麦克风权限均有旧系统实现。构建需要 Xcode 26 或更新版本。界面只显示底部图标，保留可访问性名称。颜色来自桌面 app/styles.css，功能描述来自 Town definitions。Logo 复用 beings-town-mobile 的最终移动图标。

## 边界

前台实时连接不等于 APNs/FCM。无后台常驻、APNs/FCM 推送、实时语音或完整 Markdown 扩展。现已加入持久化发送队列、运行中流恢复、附件上传解析、本地通知、已有凭据验证导入与消息筛选。平台预览与原生交互界面仍有边界，见 MOBILE-PARITY.md。Portal/Grove/Kit 与 App 管理按要求排除。
