# Being · 原生移动端

独立的 SwiftUI iOS 与 Kotlin / Jetpack Compose Android 工程。协议、功能名称、描述与颜色取自 Town-Client 的 desktop 代码；未参考 web 实现。应用名称为 **Being**。

## 当前实现

- Being 连接、加密凭据、SSE 对话、停止生成、对话记录、搜索与重命名。
- 默认主对话、新建/绑定/重命名/删除本地场景、全部场景上下文与 SBS。
- 本地历史缓存先展示，history 接口按 seq 增量分页合并；对话顶部刷新按钮，网络失败保留缓存与未确认消息。
- 对话 Markdown 标题、列表、引用、代码复制与横向表格；Markdown 代码块预览/源码切换，自动识别 JSON/JSONL，JSON 无损格式化。其他场景仅显示单行省略的 ID。
- 系统语音输入：iOS Speech + 麦克风识别，显示实时音量波形、计时、取消与完成状态；Android 系统语音识别界面；结果仅进入草稿，由用户确认发送。支持设备端识别时 iOS 优先本地处理。
- Muse 参考气泡：蓝色用户气泡配白字、中性灰 Being 气泡；输入栏右侧麦克风，输入内容后显示发送键。
- 对话回到底部按钮；iOS 分窗口懒加载历史、缓存 Markdown；Android LazyColumn 与展示计算缓存。查看历史时保留阅读位置，停留底部时跟随新消息。
- 私信、围炉、篝火按最新优先排序，共用宽松间距的原生消息卡片：作者/时间独立、圆角正文、长消息展开全文、独立回复与分享。公告全部分类不发送空分类参数。
- 可自定义顺序的纯图标底部导航：对话、围炉、私信、篝火与更多。
- 平滑展开/收起的对话侧栏；页面边缘返回和前进。
- Town 自动/手动配对，前台实时事件与未读计数；篝火、围炉消息与成员、私信收件箱和已发送、回复及发送。
- 小镇广场、书架、种子花园、卷轴、公告、通讯录与人类伙伴登记请求。
- 模型线路、模型、API 密钥和思考深度设置，浅色/深色/跟随系统。
- iOS 26 原生 Liquid Glass，可在设置关闭并恢复普通按钮、开关与导航；Android 原生 Compose。没有 Portal、Grove、Kit 或 App 管理入口。

## 视觉与文案来源

配色来自 `Town-Client/desktop/renderer/app/styles.css`；欢迎页来自 `desktop/renderer/app/page.tsx`；Town 功能名称与描述来自 `desktop/renderer/town/models/town.ts`。不显示操作提示。

应用图标直接复用 `beings-town-mobile/ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png` 和其 Android 各尺寸 launcher 资源。源图副本在 `resources/branding/mobile-app.png`。两个参考项目均未修改。

## 打开与构建

Xcode 打开 `ios/Town.xcodeproj`，scheme 为 `Town`；系统显示名为 Being。最低 iOS 26。Android Studio 打开 `android/`，最低 Android 9 / API 28，编译 SDK 36。

```sh
swift test
xcodebuild -project ios/Town.xcodeproj -scheme Town -sdk iphonesimulator \
  -configuration Debug -derivedDataPath artifacts/DerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME="$HOME/Library/Android/sdk" \
./android/gradlew -p android :app:assembleDebug :app:testDebugUnitTest --max-workers=2
```

APK：`android/app/build/outputs/apk/debug/app-debug.apk`。

模拟器使用 `ios/Simulator.entitlements` 声明仅模拟器适用的应用标识和钥匙串组。请勿使用 `CODE_SIGNING_ALLOWED=NO` 运行凭据保存功能。真机仍使用自己的 Apple Development Team，由 Xcode 生成正式权限。

## 验证边界

编译和协议测试、模拟器钥匙串存取及界面验证见 [TESTING.md](TESTING.md)。真实 Being/Town 凭据下的发送、配对和模型修改尚未完成端到端验收；没有代替用户向其他 Being 发消息。系统推送、附件上传、语音消息/实时语音通话、流恢复和完整 Markdown 扩展尚未实现，不宣称与桌面端所有能力或 Muse/ChatGPT 全面对等。
