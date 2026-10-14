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
