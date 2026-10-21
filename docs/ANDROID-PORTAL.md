# Android Portal

Android 的「更多 → 本机 Portal」提供本机工具运行时。它复用已连接 Being 的
加密凭据，通过 WSS 出站连接 Hearth `/_relay`，不监听局域网入站端口。
启动、停止、权限设置和状态是原生 Compose 界面。

## 来源与结构

- `d5z/heart-portal` 的 `android-portal` 分支，固定在
  `5cf3acb005e06d990a4157dd83a18b9ba4857554`，运行时 0.9.2，MIT。
  该提交基于先前的 `d9a9483`，已推送到上游 Android 分支。
- 参考 `HiddenFox/portal-android` 的
  `340397db82e8b99a08fa9d24d1f557930e36b76b`（App 0.1.16）：APK native
  executable、CA bundle、前台服务、重启限制、厂商后台运行指引。
- `android/portal-runtime/upstream` 是该仓库 `android-portal` 分支的 Git 子模块；
  Android Rust 适配直接维护在上游分支，主仓只固定提交，不维护补丁副本。
  Gradle 直接从子模块构建 ARM64 / x86_64，APK 不在运行时下载可执行文件。
- `PortalService` 启动 package manager 提取的 `libheart_portal.so`；它实际是
  bionic PIE executable，使用 `/system/bin/linker64`，支持 16 KB 页。
- `PortalRuntime` 读取 Android Keystore Vault 中的现有连接，通过环境变量传给
  子进程。配置文件、通知和界面不包含连接 token。
- 证书来自 Android TrustManager 系统信任库，每次启动导出至私有 CA bundle，
  再通过 `SSL_CERT_FILE` 提供给 rustls。没有关闭 TLS 验证。

## 能力与使用

| 能力 | 本次行为 |
| --- | --- |
| MCP initialize / tools list / tool call | 复用上游 JSON-RPC 协议和 relay |
| portal_status | 版本、构建哈希、实际能力与连接状态 |
| 文件读写、目录、搜索 | 默认开启，仅 Portal 专用工作区 |
| portal_web_fetch | 默认开启；Android 使用 reqwest，不依赖 curl；有总超时、大小与重定向限制，验证并固定 DNS 目标，拦截回环、私有及链路本地地址 |
| portal_exec / portal_process | 用户开启 Shell 后可用，使用 Android `/system/bin/sh` |
| 后台命令及回调 | 上游进程管理与 Heart callback；继承原有协议 |
| portal_restart | 服务监管下重启进程，保留工作区 |
| 文件导入 / 导出 | Android 系统文件选择器；单文件上限 10 MB；导入不覆盖已有文件 |
| Android 原生工具 | 日历、通讯录、提醒、时钟/拨号交接、分享、通知快捷回复、位置/地点提醒、Health Connect；默认关闭，按 Being 单独授权。详见 [前两批原生能力](ANDROID-PORTAL-NATIVE.md) |
| 截图、桌面 Kit、自定义 MCP、子代理 | 不宣告支持，配置明确禁用；未打包桌面解释器或屏幕控制权限 |

先连接 Being，再进入本机 Portal。设备名默认生成并保存；可以在停止状态下
修改设备名及能力，再点击启动。断开或更换 Being 会停止旧 Portal，需要再次手动启动。
配置切换不会把旧连接的运行时静默迁移给新 Being。

工作区位于应用 `noBackupFilesDir/portal/workspaces/<Being endpoint SHA-256>`，不同
Being 使用不同目录。旧版 `portal/workspace` 原样保留，不自动归属任何新身份。
允许 Being 修改当前工作区中的文件；需要保留的数据可导出，卸载应用会删除它们。
没有申请全盘文件访问、录音或无障碍权限；原生日历、通讯录、位置、健康权限由用户按需授予。
需要给 Being 的手机文件通过系统选择器或分享入口导入。
与参考连接器全盘读取场景不同，本 App 同时保存聊天及身份数据，因此 Shell
默认关闭。开启 Shell 后进程拥有应用 UID 权限，能够访问应用私有数据；工作区
边界仅适用于文件工具，不是 Shell 沙箱。

## 生命周期

- 仅从用户点击启动的前台页面启动 `specialUse` foreground service；通知可停止并打开设置页。
- Relay 使用上游 15 秒心跳、90 秒超时和 2–30 秒带抖动重连。
- 进程退出后等待 5 秒重启；连续三次短时间异常退出停止重试并显示失败。
- 服务运行时使用有超时的 partial wake lock，并显示耗电说明及系统电池设置入口。
- 显式停止先发送 SIGTERM，给上游最多 12 秒清理托管进程，再强制结束。
  停止期间禁止再次启动；断开 Being 同样走停止路径。
- 对尚未执行的前台启动，停止操作排在启动之后处理，先满足 Android 前台服务时限，
  再停止服务；不会启动 Portal 子进程。
- 原生进程绑定父进程死亡信号，并持有私有 runtime 文件锁，避免孤立 relay 与重复进程。
  Android shell 子进程也绑定父进程死亡信号。Shell 自行后台化的任意后代不构成安全隔离保证。
- 系统回收后允许 `START_STICKY` 恢复；系统强停、重启手机、OEM 禁止后台运行不保证自动恢复。
  Portal 不随开机启动，也不声称绕过系统 Doze。用户可在系统设置允许后台运行。
  原生提醒和地点提醒独立于 Portal 服务；开机广播仅调度系统 JobScheduler 恢复已授权的提醒。
- App 只读取 nonce 匹配的固定连接状态 JSON；不依赖日志关键词猜测是否连接，
  不把运行时 stdout、工具内容或服务端文本写入 logcat/持久日志。

## 构建

需要 JDK 17+（本地验证 JDK 21）、Android SDK 36、NDK r27c 和 Rust 1.90.0：

```sh
git submodule update --init --recursive
sdkmanager 'ndk;27.2.12479018'
rustup toolchain install 1.90.0 --profile minimal
rustup target add --toolchain 1.90.0 aarch64-linux-android x86_64-linux-android
./android/gradlew -p android :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
```

SDK 路径使用 `ANDROID_HOME` 或 `android/local.properties` 的 `sdk.dir`。
Windows 使用 `gradlew.bat`，PowerShell 请给包含点号的 `-P` 参数加引号。
默认包含 ARM64 / x86_64；`-PportalAbis=arm64-v8a` 可缩短真机开发构建时间。
仅运行 Kotlin/JVM 检查时可使用 `-x :portal-runtime:buildPortal`；这种检查不证明
APK 包含可执行运行时。正式验证及产物构建必须包含 native task。

## 隔离真机协议测试

```sh
./android/gradlew -p android :app:assembleDebug :app:assembleDebugAndroidTest \
  -PportalQa=true -PtestRunner=town.nativeapp.PortalInstrumentation
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
adb install -r android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w town.beings.nativeapp.portalqa.test/town.nativeapp.PortalInstrumentation
```

需要同时验证公网 DNS / TLS / 网页获取时，在 instrumentation 命令中加入
`-e network true`。这一项访问 `https://example.com`，其余测试只使用本地合成服务。

QA 包名为 `town.beings.nativeapp.portalqa`，不会覆盖正式应用。测试拒绝在正式包名
下执行。仅使用合成凭据与设备 loopback WebSocket 服务；真正执行 APK 内的
Portal、Service、MCP 和 Android shell，不连接真实 Being 或发送真实消息。
测试后清除 QA 连接并停止服务，截图写入 QA 包 externalFiles 中。
原有 ChatScrollInstrumentation 保持默认 runner。

具体实测结果和 review 见 `ANDROID-PORTAL-REVIEW-2026-10-20.md`。

平台依据：[原生库打包](https://developer.android.com/ndk/guides/abis)、
[前台服务类型](https://developer.android.com/develop/background-work/services/fgs/service-types)。
