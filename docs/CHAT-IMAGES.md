# 移动端回复图片与生图回执

对齐 Town-Client `b0fea26`（图片生成、原生画廊预览）。Android 和 iOS 共用相同的协议约束，分别使用 Compose / SwiftUI 渲染。

- Markdown 行内图片、独立图片、引用式图片显示在原位置，保留前后文字及完整签名 URL。代码围栏和行内代码保留源码。引用定义可跨越生图回执区块。
- 智能 UI 的正文值使用相同 Markdown 图片组件。数值指标保留原有布局。
- 点击图片打开全屏预览，支持双指缩放和平移；同一生图回执中的输出按任务、输出顺序组成画廊，支持上一张、下一张、关闭。
- HTTPS 和 raster Base64 data 图片可显示。外部下载不带 Being 凭据、Cookie；只允许 HTTPS 重定向，最多 5 次。下载上限 50 MB，校验 raster MIME，缩略图解码至 1024 像素、预览至 2048 像素。GIF 等格式显示静态解码帧。加载失败可重试。

## 生图查询

在 `being` 消息流式接收期间识别 `being.image-generation/v1` 回执并显示“正在接收图片任务回执…”，接收结束后才开始查询。任务区显示已完成数量。支持独立 JSON 对象和空语言 / json / being-image-generation 围栏，普通对象中的嵌套示例、引用和其他代码语言不查询。无效回执保留原文并提示修复。

当前移动端只配对 `https://echo.beings.town` 与 `https://beings.town`。回执 Being 必须匹配当前连接；私有 Heart 显示未配置提示，不向公共 Gateway 发送其凭据。只发 GET `/api/being-service/v1/generations/{id}` 或 `by-request/{key}`，禁止任务 API 重定向，响应限 1 MiB。返回的任务 ID、请求 key 和图片 manifest 的来源、路径必须匹配。

按服务端间隔串行轮询，间隔限制 1–60 秒且不越过截止时间。终态、待核对和截止停止轮询；断网、429、5xx 最多尝试 5 次，有限指数退避；身份或格式错误停止并提供重新查询。查询不会提交新生成。连接/消息身份改变、视图离开或应用进入后台时取消协程 / Task，回到前台恢复读取已有任务。状态和签名 URL 不写回聊天历史。

## 验证

2026-10-23 在 macOS 完成 `swift test`（77 项通过），Android `:app:testDebugUnitTest :app:lintDebug`（77 项单测通过）。Android 使用 `-x :portal-runtime:buildPortal`，本次不重新构建 Rust runtime。

协议测试覆盖回执字段、消息边界、任务身份、签名 URL、manifest 来源、轮询截止/终态、Markdown 引用与代码隔离、data MIME 和严格类型。新增流式字符分片接收、历史序列化恢复；JSON 数组和嵌套示例不触发查询，跨区块引用不污染原文。

iOS 的 `ImageGenerationUITests` 使用隔离模拟器与 loopback SSE 服务，验证流式占位、接收结束后原位显示任务卡片、前后正文和历史刷新，以及私有 Heart 不向公共 Gateway 发送凭据。真实生产 Gateway 的生图完成、签名图片下载和多图画廊仍需实际任务验收；测试不会提交付费生图任务。
