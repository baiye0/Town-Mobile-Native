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

iOS 26 TabView 和 GlassEffectContainer 使用系统玻璃效果。界面只显示底部图标，保留可访问性名称。颜色来自桌面 app/styles.css，功能描述来自 Town definitions。Logo 复用 beings-town-mobile 的最终移动图标。

## 边界

前台实时连接不等于 APNs/FCM。无后台常驻、系统推送、实时语音、附件上传、运行中流恢复或完整 Markdown 扩展。Town 已有凭据高级导入、复杂消息筛选等桌面细节仍需后续对齐。Portal/Grove/桌面 Kit 与 App 管理按要求排除。
