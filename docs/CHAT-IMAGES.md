# 移动端回复图片与生图回执

对齐 Town-Client `b0fea26`（图片生成、原生画廊预览）。Android 和 iOS 共用相同的协议约束，分别使用 Compose / SwiftUI 渲染。

- Markdown 行内图片、独立图片、引用式图片显示在原位置，保留前后文字及完整签名 URL。代码围栏和行内代码保留源码。引用定义可跨越生图回执区块。
- 智能 UI 的正文值使用相同 Markdown 图片组件。数值指标保留原有布局。
- 点击图片打开全屏预览，支持双指缩放和平移；同一生图回执中的输出按任务、输出顺序组成画廊，支持上一张、下一张、关闭。
- HTTPS 和 raster Base64 data 图片可显示。外部下载不带 Being 凭据、Cookie；只允许 HTTPS 重定向，最多 5 次。下载上限 50 MB，校验 raster MIME，缩略图解码至 1024 像素、预览至 2048 像素。GIF 等格式显示静态解码帧。加载失败可重试。

## 生图查询

只在 `being` 消息结束流式接收后识别 `being.image-generation/v1` 回执。支持独立 JSON 对象和空语言 / json / being-image-generation 围栏，普通对象中的嵌套示例、引用和其他代码语言不查询。无效回执保留原文并提示修复。

当前移动端只配对 `https://echo.beings.town` 与 `https://beings.town`。回执 Being 必须匹配当前连接；私有 Heart 显示未配置提示，不向公共 Gateway 发送其凭据。只发 GET `/api/being-service/v1/generations/{id}` 或 `by-request/{key}`，禁止任务 API 重定向，响应限 1 MiB。返回的任务 ID、请求 key 和图片 manifest 的来源、路径必须匹配。

按服务端间隔串行轮询，间隔限制 1–60 秒且不越过截止时间。终态、待核对和截止停止轮询；断网、429、5xx 最多尝试 5 次，有限指数退避；身份或格式错误停止并提供重新查询。查询不会提交新生成。连接/消息身份改变、视图离开时取消协程 / Task。状态和签名 URL 不写回聊天历史。

## 验证

Android：`:app:testDebugUnitTest :app:lintDebug :app:assembleDebug`。本次在 Windows 使用 `-x :portal-runtime:buildPortal` 复用已有 Portal 二进制，未重新构建 Rust runtime。

新增 `ImageGenerationTest` 验证回执字段、消息边界、任务身份、签名 URL、manifest 来源、轮询截止/终态、Markdown 引用与代码隔离、data MIME 和数值类型。

提交前 review 补充验证：JSON 数组内的回执示例不会触发查询；跨区块引用作为解析上下文传递，不拼接到原文，避免污染流式接收中尚未闭合的代码块。

iOS：新增 `ImageGenerationTests.swift`；需在 Mac 执行 `swift test` 和项目 Xcode 构建。Windows 无 Xcode，未宣称通过 iOS 编译。

设备验收：含签名 URL 的图片、引用图片跨回执、失败重试、缩放平移、同批次多图切换、生成完成后的原位更新、切换 Being 后不显示旧任务状态。当前环境无连接设备/模拟器，此清单仍需设备验证。
