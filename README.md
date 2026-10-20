# Being · 原生移动端

独立的 SwiftUI iOS 与 Kotlin / Jetpack Compose Android 工程。协议、功能名称、描述与颜色取自 Town-Client 的 desktop 代码；未参考 web 实现。应用名称为 **Being**。

## 当前实现

2026-10-19 双端新增发送队列与流恢复、附件上传解析、系统查看器预览、本地完成通知、原生交互界面基础组件及社区阅读细节。完整范围和剩余差异见 [移动端对齐记录](docs/MOBILE-PARITY.md)。Kit 暂不纳入移动端。

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
- 应用更新：设置页检查 `baiye0/Town-Mobile-Native` 的 GitHub 最新正式 Release。Android 可下载 Release 中的 APK 并交给系统安装器；iOS 打开 Release 发布页，实际安装通过 TestFlight 或 App Store 完成。
- iOS 16 及以上；iOS 26 使用原生 Liquid Glass，可在设置关闭并恢复普通按钮、开关与导航，旧系统自动使用普通界面；Android 原生 Compose。没有 Portal、Grove、Kit 或 App 管理入口。

## 视觉与文案来源

配色来自 `Town-Client/desktop/renderer/app/styles.css`；欢迎页来自 `desktop/renderer/app/page.tsx`；Town 功能名称与描述来自 `desktop/renderer/town/models/town.ts`。不显示操作提示。

应用图标直接复用 `beings-town-mobile/ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png` 和其 Android 各尺寸 launcher 资源。源图副本在 `resources/branding/mobile-app.png`。两个参考项目均未修改。

## 打开与构建

Xcode 26 或更新版本打开 `ios/Town.xcodeproj`，scheme 为 `Town`；系统显示名为 Being。最低 iOS 16.0，构建 SDK 版本不等于最低运行系统版本。Android Studio 打开 `android/`，最低 Android 9 / API 28，编译 SDK 36。

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

Windows 使用 JDK 21，设置 `JAVA_HOME` 指向 JDK 目录、`ANDROID_HOME` 指向 Android SDK 目录，并将 JDK 的 `bin` 和 SDK 的 `platform-tools` 加入 `PATH`。SDK 需安装 `platforms;android-36` 和 `build-tools;35.0.0`；在 `android/local.properties` 中填写 SDK 路径，例如 `sdk.dir=D\:/env/android-sdk`（目录分隔符使用 `/`，盘符冒号写作 `\:`，该文件不会提交）。环境变量设置后重新打开 PowerShell，在仓库根目录执行：

```powershell
.\android\gradlew.bat -p android :app:assembleDebug :app:testDebugUnitTest :app:lintDebug --max-workers=2
adb devices -l
adb -d install -r .\android\app\build\outputs\apk\debug\app-debug.apk
adb -d shell am start -n town.beings.nativeapp/town.nativeapp.MainActivity
```

手机需开启 USB 调试并允许此电脑连接；部分手机（如 Redmi）还需在开发者选项开启「USB 安装」，安装时如手机弹出确认，请允许安装。`-d` 选择唯一一台 USB 真机，多台真机连接时改用 `-s 设备序列号`。

模拟器使用 `ios/Simulator.entitlements` 声明仅模拟器适用的应用标识和钥匙串组。请勿使用 `CODE_SIGNING_ALLOWED=NO` 运行凭据保存功能。真机仍使用自己的 Apple Development Team，由 Xcode 生成正式权限。

## 验证边界

编译和协议测试、模拟器钥匙串存取及界面验证见 [TESTING.md](TESTING.md)。真实 Being/Town 凭据下的发送、配对和模型修改尚未完成端到端验收；没有代替用户向其他 Being 发消息。APNs/FCM 推送、语音消息录制/实时语音通话、完整桌面交互界面协议和完整 Markdown 扩展尚未实现，不宣称与桌面端所有能力或 Muse/ChatGPT 全面对等。
