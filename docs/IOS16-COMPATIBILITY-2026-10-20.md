# iOS 16 兼容性 review 与测试

日期：2026-10-20（Asia/Shanghai）。最低运行版本为 **iOS 16.0**，构建工具为 Xcode 26.6 / iOS SDK 26.5。

## 适配内容

- Debug、Release 的 Deployment Target 均改为 16.0；最终 Release 的 Info.plist `MinimumOSVersion` 和 Mach-O `minos` 均确认是 16.0。
- 六个状态模型改用 `ObservableObject` / `@Published`，所有持有者、消费者和环境注入同步改为 `StateObject`、`ObservedObject`、`EnvironmentObject`。保留聊天展示缓存的失效逻辑，内部缓存与任务句柄不触发无关界面更新。
- Liquid Glass 表面、按钮、容器和工具栏背景仅在 iOS 26 启用；旧系统使用普通界面，不显示不可用的玻璃效果设置。
- iOS 16–17 使用 `tabItem` / `tag` 导航；iOS 18 及以上保留 `Tab` 导航和系统滚动阶段 API。
- 补齐旧系统的空状态页面、图标按钮、圆形按钮、图片预览背景、字体和麦克风权限分支；改用 iOS 16 支持的 `onChange` 与工具栏位置。
- 新增共享 Town scheme、应用状态测试目标及 UI 测试目标，可以直接在 Xcode 执行测试。

原先的版本门槛来自直接调用新系统 UI API。项目原有的 Observation 状态管理也要求 iOS 17，因此支持 iOS 16 需要迁移状态模型，不能只改 Deployment Target。[Apple Observation 文档](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro)

## Review 发现并修复

1. **旧系统缺少界面更新机制**：移除 Observation 后，检查全部对象的持有、订阅和环境注入。测试确认嵌套消息修改会发布变化并使缓存失效，场景切换、草稿、未读数和导航状态仍正常更新。
2. **iOS 16 看不到“回到底部”**：实际运行发现懒加载列表的几何 preference 没有传到外层。改用可在 iOS 16 运行的直接几何监听，仅传递是否接近底部和内容高度，避免逐像素重绘整个聊天列表。
3. **拖拽取消后跳转被阻止**：用自动复位的 `GestureState` 清理拖拽状态；用户明确点击回到底部时清除残留的滚动状态。实测查看历史时刷新不会跳走，点击按钮可以到达最新消息。
4. **16.0 小版本边界**：替换 iOS 16.1 的 `fontDesign`，为 iOS 16.4 的弹层背景和 iOS 17 的圆形按钮、空状态、麦克风权限提供兼容实现。
5. **测试隔离**：聊天测试只连接测试进程提供的 loopback HTTP 服务，使用合成的 60→61 条消息；清理时核对连接地址，只断开该测试连接。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| Swift Core | 42 项通过 |
| iPhone 14 / iOS 16.4，应用状态测试 | 7 项通过 |
| iPhone 14 / iOS 16.4，UI 测试 | 4 项通过 |
| iPhone 17 / iOS 26.5，应用状态测试 | 7 项通过 |
| iPhone 17 / iOS 26.5，UI 测试 | 4 项通过 |
| iOS 16.4 深色聊天补测 | 阅读位置、回到底部及测试连接清理通过 |
| iOS Simulator Debug | 编译、签名、安装、启动通过 |
| iPhoneOS Release | 构建通过，最低系统元数据为 16.0 |
| iOS 16.4 截图检查 | 欢迎页、草稿、空状态、历史阅读、回到底部及深色欢迎页/聊天正常 |
| `git diff --check` / Xcode 项目格式 | 通过 |

UI 测试覆盖：连接表单打开/关闭；输入草稿后打开侧栏、切换标签并返回；社交与模型设置空状态；读取历史、刷新新增消息时保留位置、回到底部。iOS 26 测试保留玻璃效果开启状态。

## 本地证据

- 日志：[核心测试](../artifacts/ios16-compat/core-tests.log)、[iOS 16 测试](../artifacts/ios16-compat/ios16-tests.log)、[iOS 26 测试](../artifacts/ios16-compat/ios26-tests.log)、[Release 构建](../artifacts/ios16-compat/release-build.log)。
- 截图：[iOS 16 欢迎页](../artifacts/ios16-compat/ios16-welcome.png)、[深色](../artifacts/ios16-compat/ios16-dark.png)、[阅读历史](../artifacts/ios16-compat/ios16-history-reading-position.png)、[到达最新消息](../artifacts/ios16-compat/ios16-history-bottom.png)。
- 完整 XCTest 结果：`artifacts/ios16-compat/ios16.xcresult`、`artifacts/ios16-compat/ios26.xcresult`。
- `artifacts/` 为本机验证产物，不纳入 Git。

## 复现

使用独立、未保存真实账号连接的测试模拟器。测试会操作导航偏好并建立本地合成连接。

```sh
swift test
xcodebuild -project ios/Town.xcodeproj -scheme Town \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=Town iOS 16 Compatibility QA,OS=16.4' \
  -derivedDataPath artifacts/DerivedData-compat \
  -parallel-testing-enabled NO -jobs 4 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test
xcodebuild -project ios/Town.xcodeproj -scheme Town \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath artifacts/DerivedData-compat-release \
  -jobs 4 CODE_SIGNING_ALLOWED=NO build
```

新版系统使用 `Town iOS Compatibility QA` / iOS 26.5，或在 Xcode 中选择对应测试设备。模拟器保留 adhoc 签名以验证钥匙串路径。

## 验证边界与分发

- 最低部署目标为 16.0；实际运行验证使用 **16.4** 和 **26.5**，未逐一实测每个系统小版本，也未执行实体 iPhone 验收。
- 本轮没有用真实账号发送消息、录音或上传附件，不替代这些功能的完整真机端到端验收。已有 Ogg 本地播放问题仍以此前报告为准。
- TestFlight `0.1.0 (2)` 已于 2026-10-20 11:54:03 成功上传，签名归档的最低系统确认是 iOS 16.0；Apple 已开始处理，最终处理及测试群组分发状态尚未确认。旧构建 `0.1.0 (1)` 仍要求 iOS 26.0。详见 [发布记录](TESTFLIGHT-0.1.0.md)。
