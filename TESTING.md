# iOS 提交前 Review（2026-10-21）

## 2026-10-23 全量改动发布 Review：0.1.0（7）

- 本轮审查覆盖聊天/生图及新增 iOS Portal、系统权限、HealthKit。修复已受理发送的恢复记录过早删除、Portal 文件查询占用主线程、定位权限同步查询三处问题；详见 [发布 Review](docs/RELEASE-REVIEW-2026-10-23.md)。
- Swift Core 82 项、Android 81 项 + Lint + Debug APK、iOS TownTests 39 项、UI 13 项全部通过。iOS 初次启动挂起及重启后定位 fixture 坐标偏差已明确排除，最终 39 项无失败和跳过。
- iOS Release 归档、App Store / 开发签名 IPA、源码一致性、签名和 dSYM 校验通过。最终包 18:24 覆盖安装手机，18:25 启动成功，设备确认 0.1.0（7）；没有清除账号或聊天数据。
- 真机验证范围为安装、启动和进程存活；未使用用户生产身份发送测试对话、触发生图或读取个人健康记录。TestFlight 最终状态见 [发布记录](docs/TESTFLIGHT-0.1.0.md)。


- Review 覆盖本轮布局、侧栏、Markdown 图片、统一图片预览、智能界面宿主、上下文展示过滤和发送队列集成；Android 与 Portal 未修改。
- 修复对话切换时用“有无选择”推断智能 UI 开关的问题：开关按 Being/场景独立保存，保留用户显式开启和关闭的意图。状态回归覆盖无选择时开启、有选择时关闭、往返切换和重选当前场景。
- 修复大写 `INTELLIGENT-UI` 围栏显示正常却未参与 surface 历史与选择回传的问题；完整交互用例改用大写初始围栏，验证刷新恢复、当前选择发送和后续小写 patch 更新。
- 本轮 Swift Core **63 项**、Node 协议 **3 项**、iOS 26.5 状态 **4 项**及智能界面交互 **1 项**通过。Web 重新构建后所有生成资源与已上传构建 6 的源码清单一致；vendor 文件校验清单一致，`git diff --check` 通过。
- 证据：`artifacts/ios-review-core-20261021.log`、`artifacts/ios-review-protocol-20261021.log`、`artifacts/ios-review-web-build-20261021.log`、`artifacts/ios-review-state-20261021.xcresult`、`artifacts/ios-review-ui-20261021.xcresult`。图片保存、缩放和其他布局沿用下方已通过的验收，本轮未重复运行全部 UI 或 iOS 16.4 回归。
- 以上两处 Review 修复在 TestFlight 构建 6 上传之后完成，仅提交源码；已上传包仍对应其归档及 SHA-256 清单。

# TestFlight 0.1.0 (6)（2026-10-21）

- 用户重新要求提交后，上传已验证的最终 Release 归档；网络中断自动重试后，17:33:22 返回上传成功，命令退出 0。
- 通过 Chrome 保存测试说明并向现有外部 d5 群组提交审核。最终页面显示 **0.1.0 (6) 正在测试**，关联内部和外部 d5 群组；可通过原 TestFlight 链接安装更新。
- 日志与网页凭证：`artifacts/testflight/upload-0.1.0-6-20261021-resumed.log`、`artifacts/testflight/submitted-0.1.0-6-20261021.png`。本次复用已验证产物，未再次修改代码或重复运行测试，详见 [发布记录](docs/TESTFLIGHT-0.1.0.md)。

# iPhone 图片与智能界面更新（2026-10-21）

- 按用户要求停止 TestFlight 上传，改用 Xcode Debug 真机构建，覆盖安装到已连接的 iPhone 16 Pro Max，未卸载或清除应用数据。
- CoreDevice 确认 `town.beings.nativeapp` 已安装为 **0.1.0 (6)**，安装与启动均返回 success（17:09–17:10）。真机本轮验证为构建、覆盖安装和启动；交互回归来自前述独立 iOS 26.5 模拟器，不表述为真机完整验收。
- 证据：`artifacts/ios-image-ui-device-build.log`、`artifacts/ios-image-ui-device-install.json`、`artifacts/ios-image-ui-device-app.json`、`artifacts/ios-image-ui-device-launch.json`。
- 当时按要求终止 TestFlight 上传（退出 143）；用户随后重新要求提交，已完成上传与外测分发，见上方记录。

# 图片预览与桌面智能界面兼容（2026-10-21）

- 附件、Markdown 和智能界面图片使用统一全屏预览：双指缩放、双击放大、拖动、适合屏幕、保存到相册、文件导出和分享；导出保留原始字节，显示解码限制为最长边 4096 像素。
- 聊天展示隐藏完整的客户端能力、当前选择及界面操作上下文；原始历史不改写，代码示例和未闭合内容不误删。发送队列单独持久化界面选择，发送身份核对仍区分不同选择。
- iOS 内置桌面 MIT 渲染器，支持 tabs、diagram、图片、隔离 Worker 本地 app、跨轮 patch、版本冲突校验与回看。提供原生全屏入口；状态按 Being/场景隔离，以 JSON 保存协议空值；继续操作只填草稿。
- Swift Core 63 项、Node 协议 3 项、iOS 状态 3 项通过。iOS 26.5 图片 UI 用例通过真实双击/双指手势、系统文件导出、相册授权与保存、刷新历史和签名 URL 请求校验。智能界面用例已验证步进器、标签、选择持久化、带选择发送和跨轮 patch。
- 最终两项智能界面 UI 回归通过：标签、步进器、刷新与持久化、隐藏上下文及带选择发送、跨轮 patch、图解选择、原生图片预览、隔离 Worker 的本地计算及事件更新。全屏时移除对应内嵌渲染实例，选中标签对比度及 44 pt 操作区域已调整，截图复核通过。
- 证据：`artifacts/image-ui-core.log`、`artifacts/iui-protocol-tests.log`、`artifacts/image-ui-regression6.xcresult`（状态 3 项与图片 UI 通过；旧图解定位失败）、`artifacts/image-ui-verified.xcresult`（最终智能界面 2 项、0 failures），截图位于对应 `*-screens/`。
- 本轮未完成 iOS 16.4 UI 回归；Release 最低部署目标为 iOS 16.0。测试使用独立模拟器和 loopback 数据，不向真实 Being 发送对话。

# TestFlight 0.1.0 (5)（2026-10-21）

- Markdown 图片及侧栏遮罩修复完成 Release 归档、签名检查和上传（16:01:21）。通过 Chrome 保存测试说明并向现有外部 d5 群组提交审核，App Store Connect 最终显示“已批准”，关联内部、外部两个 d5 群组。
- 最终 IPA、归档、源码清单、日志与网页截图位于 `artifacts/testflight/`，详见 [发布记录](docs/TESTFLIGHT-0.1.0.md)。本次未重新覆盖安装 USB 真机。

# Markdown 图片与侧栏遮罩回归（2026-10-21）

- 对话正文支持内联 Markdown 图片，保留前后文字、签名查询参数和重定向；提供加载状态、失败重试及点击预览。流式回复尚未完整的图片语法保留为文本，行内代码中的图片语法不加载图片。
- 侧栏关闭时移除透明遮罩，修复遮罩仍影响主界面点击的问题。
- Swift Core 59 项通过（含 4 项新图片解析测试）。iOS 26.5 两项 UI 回归通过：图片分段到达、失败重试、预览、刷新历史、请求不带应用鉴权，以及侧栏连续三次开关与搜索键盘收起。导出截图已复核。
- iOS 16.4 本轮 UI runner 在进入测试前卡于系统 dylib 加载，未完成本轮图片 UI 回归，不记为通过。最低部署版本仍为 iOS 16.0。
- 证据：`artifacts/markdown-images-core.log`、`artifacts/ios-markdown-images-overlay.xcresult`、`artifacts/ios-markdown-images-screens/`；runner 采样：`artifacts/markdown-runner-sample.txt`。

# TestFlight 0.1.0 (4)（2026-10-21）

- 最新 iOS 布局与侧栏修复完成 Release 归档、签名校验和上传（15:29:36）。通过 Chrome 填写测试说明并向既有外部 d5 群组提交，App Store Connect 最终显示“已批准”，构建关联内部、外部两个 d5 群组。
- 本地 IPA 与归档、上传日志及网页截图保存在 `artifacts/testflight/`，详见 [发布记录](docs/TESTFLIGHT-0.1.0.md)。Markdown 图片语法暂不展示图片的现有限制已写入测试说明。

# iOS 真机覆盖安装（2026-10-21）

- 当前 UI 布局与侧栏动画修复通过 Xcode Debug 真机构建和自动签名，已覆盖安装至 USB 连接的 iPhone 16 Pro Max（iOS 27.0），保留应用数据；CoreDevice 返回安装与启动成功。
- 本轮为构建、安装及启动验证，未将模拟器 UI 回归结果视为 iOS 27 真机完整回归。日志：`artifacts/ios-device-layout-build.log`、`artifacts/ios-device-layout-install.json`、`artifacts/ios-device-layout-launch.json`。

# iOS 布局对齐 Android（2026-10-21）

- “更多”改为连接卡片、设置分组和小镇入口网格；连接、模型、外观、通知、字号、配对与更新页面统一卡片和间距，底部导航增加文字标签。未接入 Android Portal 能力。
- 篝火、围炉、私信采用紧凑操作栏；搜索、关系、时间、排序及加载数量移入筛选弹层，私信用胶囊入口切换信箱，公告改为单行轮播，消息列表保留展开、回复、分享和下拉刷新。
- Debug 模拟器构建通过。iOS 26.5 隔离模拟器验证设置与主题、关闭玻璃效果、大字号、历史阅读位置及回到底部、社交筛选与重置、收发信箱、筛选后的围炉详情、长消息展开、公告列表和详情返回。iOS 16.4 / iPhone SE 验证设置、连接弹窗与社交筛选布局。
- 截图复核覆盖浅色、深色、小屏、大字号、三类社交首屏和筛选弹层。修复公告空视图未触发首次加载、轮播条目/筛选围炉的跳转身份及公告弹层内导航作用域。
- 社交测试通过仅 Debug 模拟器可用的内存 fixture 运行，不保存配对身份、不向 Town 发送消息。聊天验证使用已有 loopback fixture。真实账号的发送、模型修改及配对流程不属于本轮 UI 验收。
- 日志与证据：`artifacts/ios-layout-social.log`、`artifacts/ios-layout-small-screen.log`、`artifacts/ios-layout-social-small.log`、`artifacts/ios-layout-final-navigation.log` 及对应 `.xcresult`；预览 `artifacts/ios-layout-preview.png`。
- 侧栏关闭改用明确的向左移出过渡，替换条件视图默认淡出；遮罩随进度消退，关闭时取消搜索焦点。iOS 26.5 验证草稿保留，iOS 26.5 与 iOS 16.4 小屏均通过连续三次开关与键盘收起；录屏抽帧确认移出后无侧栏残留。证据：`artifacts/ios-layout-sidebar-slide.xcresult`（草稿用例）、`artifacts/ios-layout-sidebar-small.xcresult`、`artifacts/ios-layout-sidebar-verified.xcresult`、`artifacts/ios-sidebar-slide.mp4`。
- 新版已覆盖安装到用户正在查看的 Town iOS Compatibility QA 模拟器，保留应用数据。未修改 Android 源码。

# Android Portal 提交前 Review 与出包（2026-10-21）

- 本轮 Review 修复三处问题：桥接鉴权读取采用总时限避免慢速连接长期占用线程；写操作在获得排队锁后重新检查身份和策略，缓存重试也受检查；待处理操作达到上限时淘汰已结束历史，保留待处理项。
- 最终 JVM 65 项通过；Android 16 模拟器完整 29 组端到端场景通过（新增慢速连接、排队撤权/切换身份、操作历史满额回归）；Lint 0 errors、62 warnings。此前 5 组权限 UI 回归通过，UI 此轮未变。
- QA 仅安装在一次性模拟器。重跑完整 QA 前需卸载模拟器旧 QA 包清除 Health Connect 旧授权，避免否定用例前提失效。没有更改手机本体或自动放开手机权限。
- 固定子模块与远程 `android-portal` 分支一致，提交 `5cf3acb005e06d990a4157dd83a18b9ba4857554`；Rust 本轮未修改，沿用该提交 323 passed、1 ignored 的记录。
- 日志：`artifacts/portal-final-review-build.log`、`artifacts/portal-final-review-emulator.log`。最终按主仓提交标识命名的 Being 本体 Debug APK 及校验元数据保存在 `artifacts/`，正式商店 Release 签名未配置。
- 地理围栏真实注册/到达、OEM 后台长测、非空健康数据仍是既有验证边界，详见 Review 文档。

# Portal 系统授权交互优化（2026-10-21）

- 开启能力会申请实际缺少的系统权限；每项独立显示 Being 策略与系统状态。拒绝、部分授权、系统不再弹窗、设置返回刷新、特殊访问、后台定位步骤均有对应提示。能力查询新增 `system_access`，不再仅报告本地开关。
- JVM 65 项通过（新增 7 项权限状态回归）；Lint 0 errors、62 warnings；Debug APK 构建成功。ARM64/x86_64 Portal ELF 与上一版逐字节一致。
- Android 16 模拟器 5 组 UI 回归通过：初始待授权、开关触发真实系统弹窗并拒绝后阻断工具、重复拒绝进入系统设置、设置返回刷新、关闭 Being 权限仍阻断工具。设置授予步骤使用模拟器 shell 授予日历读权限；没有访问真实用户数据。
- 测试 runner `town.nativeapp.PortalPermissionInstrumentation` 仅允许无连接身份的模拟器运行；真机只覆盖安装 Being 本体，不安装 QA 或测试组件、不自动放开敏感权限。
- 证据：`artifacts/portal-permissions-build.log`、`artifacts/portal-permissions-emulator-test.log`；安装包 `artifacts/being-portal-permissions-debug.apk`。
- Redmi 本体覆盖安装成功并正常冷启动，已安装 APK SHA-256 与构建产物一致：`ff746073c96244d8d738def98aebaf11bd9588eca843aada870ab558f537fb9a`。真机拒绝 ADB 注入滑动（`INJECT_EVENTS`），因此授权交互回归结论来自模拟器；没有将真机仅安装/启动检查描述为权限流程全量通过。

# 最新 Being 本体真机覆盖安装（2026-10-21）

- 已在 Redmi Note 14 Pro+ / Android 16 / ARM64 覆盖安装 `town.beings.nativeapp` 本体，保留已有账号和聊天数据。安装后从手机读取 APK SHA-256，与最终产物 `7727cffab71876e008d09a7acebd66ab68e94ea6793d15a50391df529831ec97` 完全一致。
- 正式包内 ARM64 `heart-portal --version` 执行成功（0.9.2），本体冷启动成功，已打开「本机 Portal」页面并检查截图，当前 Being 连接仍存在，页面包含手机原生能力入口，进程无 AndroidRuntime 崩溃日志。尚未启动真实 Being 的 Portal relay。
- 本轮 QA 的运行时、relay/MCP 握手通过；原生 CRUD 回归被小米禁止 ADB 代授运行时权限拦截，不能记录为新增能力全量通过。按用户要求转为直接安装 Being 本体；临时 QA 和测试组件已移除，正式应用权限未自动放开。
- 证据：`artifacts/android-native-device-install-2026-10-21.json`、`artifacts/android-native-device-launch-2026-10-21.log`、`artifacts/being-native-device-portal-2026-10-21.png`、`artifacts/android-native-device-test-2026-10-21.log`。

# Android Portal 原生能力与子模块（2026-10-21）

- 前两批接入 13 个原生 MCP 工具：日历/联系人、提醒、时钟/拨号交接、分享、通知快捷回复、位置/地理围栏、五类 Health Connect，以及授权/操作记录。默认关闭，按 Being 分离读写授权与工作区。
- Rust 适配已推送 `d5z/heart-portal` 的 `android-portal` 分支（`5cf3acb005e06d990a4157dd83a18b9ba4857554`）；主仓以 Git 子模块固定引用，无复制源码或补丁层。构建前运行 `git submodule update --init --recursive`。
- 子模块 ARM64/x86_64 与正式包名 APK 构建通过；58 项 JVM 测试通过；Lint 0 errors、61 warnings；Windows Rust 323 passed、1 ignored；Android 16 模拟器 26 组端到端场景通过。签名、zipalign、16 KB ELF 对齐检查通过。
- 真机安装时 USB/ADB 反复断开，本轮新增原生能力未完成 Redmi 验证，未覆盖正式 Being。地理围栏只完成注册失败回滚验证，真实到达/离开、OEM 后台长测和实际健康记录仍需设备验收。
- 安装包：`artifacts/being-portal-debug.apk`；[能力与用法](docs/ANDROID-PORTAL-NATIVE.md)；[完整 Review、测试证据和验收边界](docs/ANDROID-PORTAL-NATIVE-REVIEW-2026-10-21.md)。下方记录均为各自时间点的历史结果。

# Android Portal 真机补充验证（2026-10-21）

- Redmi Note 14 Pro+ / Android 16 / API 36 / ARM64：独立 QA 应用和测试组件安装成功，11 组端到端测试全部通过，包含真实 HTTPS 获取、文件边界、后台回调、重连、崩溃恢复、受控重启及快速启停。
- 使用上一轮构建产物，生产代码无新增变更；测试清理合成身份并停止服务，无残留 Portal 进程，未覆盖原 Being 应用或发送真实 Being 消息。
- 日志：`artifacts/portal-device-instrumentation-2026-10-21.txt`；截图：`artifacts/portal-device-qa-2026-10-21.png`。真实 Being WSS 联调、OEM 后台长测及系统文件选择器等交互仍待验收。
- 详细结果见 [Portal Review](docs/ANDROID-PORTAL-REVIEW-2026-10-20.md)。下方安装限制是前一日记录，现已解除并完成本次验证。

# Android 内置 Portal（2026-10-20）

- 参考 heart-portal/android-portal 和 HiddenFox/portal-android，内置固定版本 Rust 运行时，通过「更多 → 本机 Portal」启停；提供专用工作区、网页获取、可选 Shell、前台服务与重连恢复。
- 最终 ARM64 / x86_64 Debug APK 构建通过；54 项 JVM 测试通过；Lint 0 errors、52 warnings；git diff --check 通过。
- Android 16 x86_64 模拟器独立 QA 应用 11 组端到端验证通过：真实运行时/Service/relay/MCP、文件与边界、HTTPS 网页、断线重连、后台回调、命令超时、崩溃恢复、重启、停止、能力关闭与启动后立即停止。
- Review 修复了 Android TOML 路径转义、能力关闭仍能直接调用、curl 不可用、前台服务快速启停超时及状态清理时序问题。实际截图复核通过。
- Redmi 阻止 QA APK USB 安装，本轮没有完成真机运行验证；真实 Being WSS 联调、OEM 后台长测和部分系统 UI 交互仍未覆盖。没有发送真实 Being 消息。
- 安装包：`artifacts/being-portal-debug.apk`；完整实现、复现命令、日志和验收边界见 [Portal Review](docs/ANDROID-PORTAL-REVIEW-2026-10-20.md)。

# Android 提交前 Review（2026-10-20）

- Review 范围：设置与社交页面布局、消息正文与菜单、流式分段与历史合并、回到底部协调器、输入框配色及相关测试。
- 修复排队提问插入上一轮多段回复之间的问题：本地提问跟随上一轮的所有回复，而非仅跟随入队时已有的气泡。新增回归测试先复现失败，再验证多段回复、部分历史确认及缓存恢复后的顺序。
- 补回围炉内「更多操作 → 刷新消息」入口；附件气泡外的场景标签改用主题文字色，避免浅色背景上的白字。
- 另一任务同时在当前目录开发 Portal，因此本次使用独立快照验证并提交 UI／对话改动，未包含 Portal 源码、服务或构建接入。
- 独立快照的 Debug APK、AndroidTest APK、51 项 JVM 测试及 Lint 均通过，Lint 0 errors、34 warnings。日志：`artifacts/review-final-build.log`；代码通过 `git diff --check`。
- Redmi 上应用 APK 覆盖安装成功；本次 AndroidTest APK 安装被系统以 `INSTALL_FAILED_USER_RESTRICTED` 拒绝，因此未重跑真机滚动测试。下方 8 项真机回归属于此前验证，不代表本次重测。未向真实 Being 发送测试消息。

# Android 回到底部修复与真机布局回归（2026-10-20）

- 使用单一 `ChatScrollController` 协调回到底部、自动跟随、长回复定位与索引跳转，删除按钮动画与采样跳转之间的竞争。滚动等待当前消息列表完成测量，以带稳定 key 的尾部占位为目标；手动回到底部优先接管已有滚动，即使旧滚动尚未离开底部。
- 手动回到底部后保持显式跟随，后续流式分段不会重新触发长回复开头定位。监听实际尾部尺寸和视口，覆盖附件延迟展开、输入区高度变化；翻阅历史时不自动抢位置。
- Redmi Note 14 Pro+ / Android 16 上运行 `ChatScrollInstrumentation`，8 项实测通过：超长历史初始定位、追加消息期间重复点击、长回复/新气泡显式跟随、视口收缩与延迟内容重排、历史阅读不被打断、长回复定位后回到底部、连续 10 次请求与追加、接管进行中的滚动。断言检查实测 footer 可见、内容与视口尺寸匹配、不可再向下滚动及旧滚动取消。
- 测试使用 Debug 专用、受 shell 权限保护的空 Activity 与合成数据；直接调用生产按钮回调和滚动协调器，真实测量 Compose LazyColumn，不注入触屏事件、不修改 USB 安全设置、不发送真实对话。视口变化模拟输入区/键盘占位，未驱动系统输入法。
- 复现：构建并安装 Debug 与 AndroidTest APK，运行 `adb shell am instrument -w town.beings.nativeapp.test/town.nativeapp.ChatScrollInstrumentation`；成功输出 `PASS 8 scroll scenarios`。记录位于 `artifacts/scroll-device-test.log`。
- Debug/AndroidTest 构建、50 项 JVM 测试和 Lint 均通过；修复版已覆盖安装到手机，原有数据保留。

# Android 对话交互与流式回复对齐 iOS（2026-10-20）

- 对照 `ios/Town/TownApp.swift`、`ChatRunView.swift`、`DeliveryStore.swift`、`Core/ReplyStream.swift` 和 `Core/HistoryRules.swift` 调整 Android；移除常驻消息省略号，长按气泡打开复制、引用、分享。普通 Markdown 在气泡内不再用段落级选区截获长按；代码块仍有独立复制功能。提问索引按最新提问在前展示。
- 用户消息在持久化队列成功后立即回显，包含附件-only 消息；正常准备/发送不再显示多余状态标签，排队、失败、待确认和停止仍保留。附件外层不再包蓝色底，正文维持独立气泡。
- `message_stop` 结束单个回复气泡，EOF/完成事件结束整轮；工具前后正文以段落分隔，思考/工具内容属于发起提问的独立过程区域，运行时预览，结束后折叠。接受 `delta.text` 的不同类型标签与 `delta.thinking`，忽略非 JSON 心跳，50 ms 合并展示更新并在退出时刷新最后一帧。
- 为消息与流式分段保存稳定标识、顺序锚点、服务端序号及进行状态；历史确认保留原位置和过程，流式中不覆盖实时正文，完成后使用确认正文。仅对唯一且足够长的旧版拼接回复迁移重复终稿，保留前文过程。
- 短回复跟随尾部；长回复填满视口后定位开头；手动翻阅与索引跳转暂停跟随，输入框聚焦/新提问/回到底部恢复跟随。键盘与输入框高度变化通过视口更新保持尾部可见。
- `:app:assembleDebug :app:testDebugUnitTest :app:lintDebug --offline` 通过，50 项 JVM 测试通过（新增 15 项），Lint 0 errors。新增测试覆盖 SSE 心跳/分段、思考隔离、服务端确认与继续输出、历史期间过程更新、重复正文身份、思考期间排队顺序、旧记录迁移、最后一帧刷新及滚动决策。
- Redmi Note 14 Pro+ 覆盖安装并启动成功；现有对话截图 `artifacts/being-ios-parity.png` 确认气泡旁不再显示省略号按钮，当前应用进程的崩溃日志为空。
- 上述 JVM 测试验证状态与决策，不替代长按、键盘动画、持续流式和附件播放的真机交互验收；未向真实 Being 发送测试消息。

# Android 篝火与围炉顶部空间优化（2026-10-20）

- 将标题下方多排固定控件合并为一行图标操作栏；围炉名称和返回入口同行，成员入口收进菜单。搜索、作者/关系/时间筛选、排序及篝火加载条数移至可滚动底部面板，选项自动换行。
- 公告改为置顶优先的单行轮播，随消息列表滚动，菜单保留全部公告入口。减少列表顶部空白与消息间距，筛选生效显示标记，无匹配结果支持一键清除。
- 进入/退出围炉重置搜索与筛选，避免围炉名称被用于过滤消息；切换围炉或邮箱回到列表顶部，普通刷新不强制改变阅读位置。
- `:app:assembleDebug :app:testDebugUnitTest :app:lintDebug --offline` 通过；35 项 JVM 测试通过，Lint 0 errors、42 warnings、1 hint。未新增仅映射布局实现的单元测试。
- 已在 Redmi Note 14 Pro+ 覆盖安装更新，保留原有应用数据，启动成功。
- 设备未授权模拟点击，当前停在主对话；篝火/围炉页面的真机视觉效果、筛选面板和公告交互仍需手动验收，编译与 JVM 测试不代表这些验证已经完成。

# Android 设置布局与消息正文修复（2026-10-20）

- 修复普通用户消息未渲染正文的问题：纯文字提问由 `UserMessageBody` 显示；附件消息保留附件卡片与独立正文，过滤附件引用标记和客户端上下文。
- 提问索引移至顶部图标，使用可搜索的底部面板；过滤结果保留原始消息位置和提问序号。复制正文、引用到草稿位于气泡外的消息菜单中。
- 设置首页采用分组卡片和小镇入口网格；连接、配对、模型、通知、外观、字号和导航页统一图标、间距与标题。通知选项只在通知页维护，更新检查放在独立页面。
- 连续回复的自动滚动由等待停顿改为 80 ms 采样；修正无附件发送时的准备状态文案。未改动服务端协议。
- `:app:assembleDebug :app:testDebugUnitTest :app:lintDebug` 通过；Android JVM 35 项测试通过，Lint 0 errors。新增 4 项覆盖普通提问正文、附件内部内容隐藏、索引过滤定位和附件名称搜索。
- Redmi Note 14 Pro+ / Android 16 覆盖安装并启动成功；截图和 UI 层级确认已有“你好”正文可见、提问索引为图标、引用文字与引用图标不再显示在气泡中；启动崩溃日志为空。
- 未发送新的测试对话。设备未授权模拟点击，未完成设置各页、消息菜单交互、深色/大字号与持续流式滚动的完整真机验收；这些验证不以编译或 JVM 测试代替。

# TestFlight 0.1.0 (3)（2026-10-20）

- 当前修复版本已于 15:00:04（Asia/Shanghai）通过 Xcode 上传成功，Apple 已开始处理；最终处理与测试群组分发状态尚未确认。
- Release 归档、签名、dSYM 与最低系统 iOS 16.0 校验通过。详见 [发布记录](docs/TESTFLIGHT-0.1.0.md)。

# 实时正文与独立思考过程（2026-10-20）

- 思考/工具过程独立显示在提问与回复之间，正文出现前可预览和展开，结束后收起并保留；历史确认提问后过程仍继续更新。
- SSE 非 JSON 数据不再导致退出读取；按 Town-Client 接收 `delta.text`，补充 `delta.thinking`。有意分段的 UI 测试逐段断言屏幕正文，在三段均可见后才结束连接。
- Swift Core 55 项、iOS 16.4 状态测试 11 项通过；iOS 16.4 的新增分段/过程与消息顺序 UI 测试通过，iOS 26.5 的分段/过程、消息顺序、长回复阅读及输入框定位 4 项 UI 测试通过。历史确认分支另跑 iOS 16 状态回归通过。
- iPhoneOS 签名 Debug 构建通过，最低系统 16.0。真实服务的那次网络事件未抓取，不能把可复现的容错缺陷断言为该次现象的唯一原因。详见 [对话流 Review 报告](docs/CHAT-FLOW-REVIEW-2026-10-20.md)。
- 最后的历史确认分支修改，另通过 iOS 26.5“思考期间刷新历史 → 多段正文 → 过程收起保留”的完整 UI 回归。

# 输入框聚焦回到底部（2026-10-20）

- 点击输入框自动回到最新消息；键盘完成展开和多行输入改变可视高度时保持底部可见。手动翻阅历史后不强拉，再次聚焦时重新回到底部。
- iOS 16.4、26.5 各通过新增焦点/多行输入/再次聚焦用例，并通过长回复锚定及历史阅读两项相关回归；结果分布于分次测试运行，详见 [对话流 Review 报告](docs/CHAT-FLOW-REVIEW-2026-10-20.md)。
- 本项尚未提交或上传 TestFlight。

# iOS 对话流、输入栏与相机回归（2026-10-20）

- 参照 Town-Client `9268a40` 对齐即时回显、回复边界、历史身份合并、长回复阅读和优先发送/排队操作。
- 修复回复跳到提问上方、正常发送状态持续显示、输入触发历史重绘、相机上下白边和加号旁输入间距。
- Swift Core 53 项通过；iOS 16.4 与 iOS 26.5 各通过 10 项状态测试、8 项 UI 测试。iOS 16 在最后的身份合并审查修改后另跑状态回归；iOS 26 运行最终完整套件。
- 最终 iPhoneOS Release 构建通过，最低系统仍为 iOS 16.0；本轮未提交或重新上传 TestFlight。
- 实现差异、测试失败修复过程和真机验证边界见 [对话流 Review 报告](docs/CHAT-FLOW-REVIEW-2026-10-20.md)。

# iOS 16 兼容性验收（2026-10-20）

- 最低系统改为 iOS 16.0；状态管理、导航、玻璃效果、空状态、麦克风权限和聊天滚动完成适配。
- Swift Core 42 项通过；iOS 16.4 和 iOS 26.5 各通过 7 项状态测试、4 项 UI 测试。
- 修复旧系统历史阅读时回到底部按钮缺失及拖拽状态残留；使用本地合成服务验证 60→61 条消息刷新和阅读位置保留。
- Simulator Debug 与 iPhoneOS Release 构建通过；安装包和二进制的最低系统均为 16.0。
- 完整 review、截图、命令及验证边界见 [iOS 16 兼容报告](docs/IOS16-COMPATIBILITY-2026-10-20.md)。支持 iOS 16 的 TestFlight `0.1.0 (2)` 已成功上传，Apple 已开始处理；最终处理及测试群组分发状态尚未确认，见 [发布记录](docs/TESTFLIGHT-0.1.0.md)。

# iOS 正式应用多模态手动验收（2026-10-19）

- 使用 Computer Use、用户提供的真实 Being 连接和本机 19 个合成多模态样本完成上传与回显检查；完整矩阵见 [手动验收报告](docs/IOS-MANUAL-REVIEW-2026-10-19.md)。
- 修复普通用户正文消失、纯附件即时回显、转写版本刷新、历史解析文字泄漏、图片预览布局、空白提问索引和预览标题。
- 按最新要求移除 iOS 通用附件卡片的解析状态与“解析文字”入口；图片仅显示图片，音频保留播放器与转写。
- 实测 MP3/WAV/M4A 播放通过；Ogg Vorbis/Opus 上传和转写通过但本地播放失败，不能宣称所有格式通过。停止生成受自动化超时影响未可靠验证。
- Swift Core 32 项通过，最终 iOS Simulator Debug 构建通过。截图与具体限制见报告。

# 图片、音频附件与 SBS 状态点（2026-10-19）

- 图片隐藏文件名、解析入口和解析进度，保留缩略图与点击放大；缩略图采用限尺寸解码。
- 音频对齐桌面内嵌播放器：真实波形（超过解码预算使用中性占位条）、播放/暂停、拖动进度、时长、音量、0.5–2 倍速和保存入口。转写直接显示在下方，保留多人及不确定说话人标记。离开页面或应用进入后台暂停播放。
- SBS 顶部和设置页统一绿色状态点；关闭/未知空心，活动时呼吸；结束事件清除活动状态。
- Swift Core 30 项、Android JVM 31 项通过；iOS Simulator Debug 与 Android Debug 构建通过；Android Lint 0 errors。
- 独立 iOS 测试应用使用本地生成音频和图片验证：图片无文件名/解析按钮、点击放大、音频从 0:00 播放到 0:07 后暂停、菜单、切换 2×、内联转写及三种状态点。截图：`artifacts/media-attachments-ios.png`。测试入口仅存在于临时目录，不纳入产品。
- Android 未连接模拟器/真机，本轮未做音频控件 GUI 验证；网络附件读取和真实音频格式兼容性尚需设备验收。

# SBS 顶部状态与开关

- iOS、Android 均从对话顶部展开 SBS 设置；正文开关按连接和场景保存，全部场景模式保留原场景偏好。
- 自主醒来发送 PATCH，等待 `ok` 与 `config.sbs_enabled` 确认；失败保留原值并显示错误。未使用真实账号切换服务端配置。
- 前台 10 秒轮询；退出对话/进入后台取消循环。无场景的自主来源才显示 SBS 状态，普通对话和已结束流不会被误标为 SBS；异常快照不会清掉已知状态。
- 新增双端测试覆盖普通对话、已结束活动、带场景流、无效快照、工具阶段与回调标签。Swift 27 项、Android JVM 28 项测试通过；双端 Debug 构建通过，Android Lint 0 errors。

# 浅色对话与历史读取修复

- 用户消息背景改为 `#005FCC`，白色文字对比度约 6.0:1；跨场景标签跟随消息文字色，避免灰字落在蓝底上。
- 初次无缓存时读取最近 500 条历史（与桌面初次读取方式一致），有游标时仍完整增量分页，不跳过离线期间的消息。
- 分开提示网络超时、凭据/HTTP 错误、数据格式错误与缓存保存失败；重试时清理历史旧提示，取消请求与旧连接返回不再报错。
- 新增双端回归测试覆盖首次/增量请求与错误分类，并确认不展示异常中的敏感原文。
- 验证：Swift 26 项、Android JVM 27 项测试通过；iOS Simulator Debug 与 Android Debug 构建通过，Android Lint 无错误。
- 截图不能确定当时失败的具体网络/存储原因，本轮未使用真实账号复现。

# 2026-10-19 移动端对齐验证

本轮范围见 [MOBILE-PARITY.md](docs/MOBILE-PARITY.md)。Kit 按用户要求排除。

- Swift Core：25 项测试通过。新增队列恢复快照、回放序号、历史附件/过程元数据、关系筛选和原生交互文档测试。
- Android JVM：26 项测试通过，0 失败、0 错误、0 跳过。
- iOS Simulator Debug：构建通过；在新建的 Town Parity QA 模拟器中安装启动，检查欢迎页、顶部导航和输入栏，截图位于忽略的 `artifacts/parity-ios-welcome.png`。
- Android Debug APK：构建通过；Lint 为 0 errors、39 warnings、1 hint。未连接 Android 模拟器/真机，未把构建结果表述为完整 GUI 验收。
- 没有使用真实身份发送消息、上传附件、导入凭据或改变通知偏好。网络写入、断网/重启完整链路、各系统文件查看器及通知点击仍需测试账号与设备验收。
- 本地完成通知不等于后台 APNs/FCM 推送；原生交互界面只实现明确声明的协议子集，不执行生成脚本或跨轮 surface patch。

以下为保留的历史验证记录，旧记录中的“尚未实现”描述以本轮对齐文档为准。

---

# 验证记录

日期：2026-10-14。参考范围仅为 Town-Client 的 desktop 代码和用户提供的移动端截图，没有参考 web 实现。

## 本轮结果

| 检查 | 结果 |
| --- | --- |
| Swift Core 回归测试 | 18 项通过 |
| Android JVM 回归测试 | 20 项通过，0 失败、0 跳过 |
| iOS 26.5 Simulator Debug | 构建通过，保留数据覆盖安装并运行 |
| iOS 真机 Debug 签名构建 | 通过；上一版已安装到已连接手机，本轮最终版未重新安装（设备离线） |
| Android Debug APK | 构建通过，模拟器保留数据覆盖安装、启动检查 |
| Android Lint | 0 errors；35 warnings、1 hint，主要为依赖更新、原样复用的图标、SharedPreferences 写法和备份配置建议 |
| 公开 Town GET | /api、书架、种子、公告、通讯录均 HTTP 200，顶层字段与解析一致 |
| 提交文件检查 | 构建产物、用户缓存、设备凭据、签名材料、个人开发路径不纳入 Git |

## 本轮修复

- 围炉成员与 desktop 的字段优先级一致：字符串/数字名单、裸数组、members 数组、displayName/display/id 均支持。按身份去重，同名不同身份分别保留；显示加入时间，提供加载、空状态和失败重试。名单错误格式不会伪装成成功空列表。
- iOS 社交流和目录列表增加请求版本校验，避免旧请求覆盖新筛选；身份变化清除旧内容和弹层。
- Android 社交/目录页面按栏目及身份隔离 Compose 状态，防止切换后沿用旧围炉、筛选或详情。
- “我的卷轴”兼容新 Town ID 的 author 参数及旧 Being ID 的 being_id 参数。
- Android 本地消息缓存完整保存/恢复 timestamp、kind、scene_label，兼容旧缓存，避免重启丢失时间和系统标记。
- 双端连接切换清空旧草稿并恢复对应缓存，避免把上个 Being 的草稿带入新连接。
- Android 缓存展示消息计算结果，减少草稿输入时重复合并全历史；输入栏最小高度 48dp、垂直居中、底部间距 10dp，并支持点击消息区域失焦。
- 本轮之前已修复的空回复占位、思考三点动画、iOS 懒加载窗口和 Markdown 缓存纳入本次提交。

## iOS 实际界面回归

在 Town Native QA 使用原有连接，只读查看真实数据，没有发送消息。

- 深色对话：蓝色用户气泡、灰色 Being 气泡，短文本按内容收缩；空回复占位不显示。
- 聚焦输入栏并显示系统软件键盘：输入栏在键盘上方，没有重叠；点击对话空白处收起键盘，无额外收键盘按钮。
- 全部场景上下文：查看长回复，其他场景 ID 单行省略；点击“回到底部”到达最后一条内容。验证后恢复原上下文偏好。
- 围炉：列表、详情长文预览、暖色卡片；成员页实际显示姓名、Town ID 与加入时间。
- 设置：浅色/深色可读；玻璃开关切换后只有一条底部导航。验证后恢复原深色、关闭玻璃的偏好。
- 模型设置：真实读取线路、模型和思考深度，未提交配置。
- 公告：实际显示公告内容；卷轴公开列表与“我的卷轴”均实际加载；导航配置页面展示正常。
- 前序回归记录：已复现并修复新建场景数组越界，成功创建测试场景；模拟器钥匙串随机 QA 条目 add/update/read/delete 均为成功状态。没有读取或覆盖用户钥匙串内容。

## 自动化覆盖

连接地址校验、SSE UTF-8/CRLF 分帧、配对码完整性及歧义、Town 身份验证、部分 history 合并、重复本地消息逐条匹配、空回复占位移除且保留部分正文、场景隔离、消息角色/标记、时间排序与时区、公告过滤、回复上下文、Markdown 代码/表格、JSON/JSONL 无损格式化、成员混合格式和身份去重、Android 缓存元数据往返读写。

## 验证限制及剩余能力

- Android GUI 模拟器已启动，但当前桌面 UI 工具无法识别其窗口。因此 Android 逐页手势、键盘、浅深色截图和实际成员页交互尚未完成，不能以构建或 JVM 测试代替此项验收。
- 没有代替用户执行真实 Town 发言、私信、自动配对、模型修改、公开通讯录登记，也没有录制用户声音。相关接口契约有测试，真实写入端到端流程仍需在测试账号验证。
- iOS 本轮界面抽查不等于所有设备尺寸、系统字号、旋转及长时间压力测试。没有提供实测 FPS 或内存峰值结论。
- Xcode 尚有 iPad 全方向支持建议和无 AppIntents 的元数据提示；Android 保留上述非阻断 Lint 建议，没有为本次修复批量升级依赖或改动指定 logo。
- 系统推送、附件上传、语音消息/实时通话、流恢复和完整 Markdown 扩展尚未实现。不能宣称与 desktop 或 Muse 全功能对等。

## 复现命令

```sh
swift test
xcodebuild -project ios/Town.xcodeproj -scheme Town -sdk iphonesimulator \
  -configuration Debug -derivedDataPath artifacts/DerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
./android/gradlew -p android :app:assembleDebug :app:testDebugUnitTest :app:lintDebug --max-workers=2
```

Android 使用 JDK 21 和 SDK 36。真机在 Xcode 选择自己的 Development Team。模拟器不能用 CODE_SIGNING_ALLOWED=NO，否则钥匙串权限不正确。

## 2026-10-23：iOS 本机 Portal

新增原生 Swift Portal，入口为“更多 → 本机 Portal”。实现及平台边界见
[IOS-PORTAL.md](docs/IOS-PORTAL.md)。参考 Android 的固定版本 relay 协议和 nanoMuse
的原生能力/权限设计；未引入外部运行时或第三方源码。

### 验证范围

- `swift test`：67 项通过，新增 4 项覆盖 relay URL/身份隔离、设备名与请求指纹、
  路径穿越/绝对路径/悬空和父级符号链接、导入大小/同名保护、字面搜索。
  工作区统一使用物理路径，修复 Foundation `/var` 与枚举结果 `/private/var` 别名不一致。
- iOS 26.5 独立模拟器 `Town Portal Isolated QA`：26 项 TownTests + 2 项 Portal 页面测试通过。
  覆盖 loopback **真实 URLSession WebSocket** 握手、MCP 初始化和文件写读、后台暂停/恢复、
  切换身份停止、握手拒绝且不回显服务端内容、损坏配置拒绝访问、写入中断恢复为 unknown。
- 正向系统测试在隔离模拟器上授予日历、提醒、联系人和定位权限：创建唯一命名的合成数据，
  验证待确认阶段没有写入、确认后创建、相同 request_id 去重、参数冲突拒绝、撤权取消、
  目标记录变化拒绝旧操作、提醒完成和删除。定位使用 `31.2304,121.4737` 模拟坐标。
  测试清理合成记录，原生正向用例拒绝在真机执行。
- iOS 16.4 独立模拟器 `Town Portal iOS 16 QA`：10 项 Portal 单元/集成测试 + 2 项 UI 测试通过，
  包含已授权的原生正向测试。旧系统采用普通展开按钮，避免 DisclosureGroup 的可访问性差异。
- UI 测试覆盖：未连接禁用启动、已连接启停/设备名锁定、展开权限、工作区入口；
  已导出并查看页面截图。iOS 26.5 的读写开关与系统授权独立显示。
- `git diff --check` 通过。iOS 工程仍支持最低 iOS 16，无新增 Swift Package 或 native 构建依赖。

### 产物与未覆盖项

测试构建位于 `artifacts/PortalDerivedData/`；本轮日志和截图汇总在
`artifacts/ios-portal-qa/`（均为本地产物，不纳入 Git）。

未使用真实 Being 凭据或发送真实消息；真实公网 relay、设备睡眠/长时间网络切换、
真实系统权限弹窗及拒绝恢复、iOS 部分联系人、大致定位、账号同步、提醒通知交付、
系统文件选择器云盘下载与大文件导出仍需真机端到端验收。模拟器权限由 `simctl privacy`
授予，不能证明真实权限申请弹窗已验收。iOS 不保证后台常驻；未宣告未实现的 Shell、
网页抓取、通知读取、地点提醒、分享扩展等能力。健康数据已在下述补充实现。

## 2026-10-23：授权修复与 HealthKit

- 修复未等待系统权限就保存开启状态的问题；定位等待 delegate 回调。拒绝后保持关闭，已拒绝的权限提供系统设置入口，返回前台清除失效授权。
- HealthKit 只读开放活动、睡眠、锻炼、心肺和身体指标共 26 类；使用“关联 Apple 健康”直接唤起系统共享选择页，完成后关联当前 Being；提供断开入口，不再使用逐类授权按钮或开关。系统流程成功不视为读取授权成功，空结果不视为零。健康返回值不写入 Portal 日志或磁盘。
- 新增 9 项 `IOSPortalPermissionTests`：拒绝/设置恢复、等待系统结果、授权中切换 Being、撤销中的授权回调、旧配置修复、关联入口发起系统共享选择并准确区分关联状态与系统读取状态、取消流程、跨身份隔离、查询中撤销、时间范围及单位转换。
- `swift test` 67 项通过；iOS 26.5 共 34 项 TownTests 通过；原有 2 项 Portal UI 测试通过。新增真实日历拒绝弹窗 UI 测试通过；健康关联及断开见最终回归记录。
- 正向定位测试需先启动指定模拟器并设置合成坐标，使用 `-parallel-testing-enabled NO`，避免 Xcode 的克隆设备丢失坐标。原生 EventKit 延迟初始化，测试结束释放 store，避免大量测试实例耗尽系统连接。
- iOS 16.4 的 9 项新增授权及契约测试通过。
- iOS 设备 Debug 构建通过，已覆盖安装并启动在连接的 iPhone 16 Pro Max 上。签名产物确认包含 `com.apple.developer.healthkit`，未申请健康写入或后台交付 entitlement。
- 尚未在用户手机上读取真实健康记录，也未代替用户选择系统健康权限；真实 Being 公网数据交付仍需用户连接后验收。

### 参数契约修复（0.2.0-ios）

用户反馈旧 `portal_ios_health` 仅返回“参数缺失或包含不支持的字段”。原因是旧接口强制 category/start/end，统一错误没有给出缺项和契约，尚未进入 HealthKit 查询。
新接口只要求 category，默认最近 7 天；capabilities 返回 schema、类别、单位、示例，校验错误提供具体诊断。
增加契约回归测试（错误字段、缺失 category、有效最小参数、默认日期、类别唯一性、血氧百分比换算）以及隔离模拟器全部 26 类 HealthKit 实际查询测试。

最终验证：
- iOS 26.5：9 项授权/契约单元测试 + 1 项实际 HealthKit 查询测试通过；24 类真实系统查询返回有效结构。当前模拟器不在共享选择页提供血压两项，这两项返回系统错误 5；用例明确核对该限制，不把错误伪造成空数据或全量成功。
- UI：健康关联说明卡片、取消、系统选择页、拒绝与系统“好”确认、允许全部共享、显示关联状态、断开关联均通过。截图导出并检查。
- iOS 16.4：9 项授权/契约回归通过。纯核心 `swift test` 67 项通过。最终设备构建通过，0.2.0-ios 已覆盖安装到 iPhone 16 Pro Max。
- 最终日志：`artifacts/ios-portal-qa/town-health-native-complete.log`、`town-health-positive-ui.log`、`town-health-expanded-verified.log`（早期组合测试包含前置权限未完成的失败，后续已单独完成实际查询测试）、`town-health-expanded-ios16.log`。
- 原生查询 QA 必须先在同一隔离模拟器运行 `CompatibilityUITests/testPortalHealthSuccessfulConnection`，再运行 `IOSPortalTests/testHealthKitQueriesAllSupportedTypesOnIsolatedSimulator`；未准备系统选择时后者跳过。未验证用户手机非空健康记录，也未向真实 Being 传输个人健康数据。

### 健康“继续”后结果页修复

- 移除健康关联请求结束后无条件关闭说明页的逻辑；完成保留结果和共享范围修改指引，用户点“完成”再退出。失败保留提示与重试入口。
- `connectHealth` 返回实际流程结果：系统请求异常、身份变化、保存失败均不显示完成；已有健康关联不能掩盖本次请求失败。
- iOS 26.5：11 项授权/契约单元测试及 2 项系统权限 UI 测试通过。覆盖请求取消、已关联时重试失败、配置保存失败，以及首次允许、拒绝、重复请求直接返回时结果页仍可见。
- 设备 Debug 构建通过，已覆盖安装并启动到连接的 iPhone 16 Pro Max。没有读取真实手机健康记录。
- 日志：`artifacts/ios-portal-qa/town-health-visible-result.log`、`town-health-visible-result-device.log`；截图位于 `health-visible-result-screenshots/`。
