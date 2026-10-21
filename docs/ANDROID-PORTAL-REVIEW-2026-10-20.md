# Android Portal 实现与 Review

日期：2026-10-20。采用内置源码模块，将 Heart Portal 0.9.2 接入 Android App。
入口为「更多 → 本机 Portal」。参考版本与许可证见
[UPSTREAM.md](../android/portal-runtime/UPSTREAM.md)，使用与构建见
[ANDROID-PORTAL.md](ANDROID-PORTAL.md)。

## 交付范围

- Gradle 从固定 Cargo.lock 源码构建 ARM64 / x86_64 原生运行时，随 APK 打包。
- 原生 Compose 设置页、现有 Being 身份复用、前台通知与停止、连接状态、重连、
  进程恢复、受控重启、电池设置指引和专用工作区文件导入/导出。
- MCP 文件读写/编辑/搜索、网页获取；用户开启后支持 Shell、后台进程与回调。
- Shell 默认关闭；截图、桌面 Kit、自定义 MCP、子代理明确禁用。

## Review 中发现并修复

| 问题 | 修复及验证 |
| --- | --- |
| Android JSONObject.quote 将路径斜线编码为 TOML 不支持的转义，导致运行时启动即退出 | 独立 TOML 字符串编码；JVM 转义回归与实际 Android 启动成功 |
| 上游文件/搜索/网页开关只控制工具发现，直接 tools/call 仍可执行 | 在调用入口校验能力；逐个直调关闭的工具，验证明确拒绝 |
| 上游网页工具依赖 Android 系统不存在的 curl | Android 分支用 reqwest 流式读取、固定经验证的 DNS 地址、每次重定向重新验证、限制时间与字节；真实 HTTPS 获取成功 |
| 开始后立即 stopService 可取消尚未执行的前台启动，触发系统 ForegroundServiceDidNotStartInTimeException | 将启动阶段的停止排在启动命令之后；服务先进入前台再处理取消；回归等待延迟超时窗口后通过 |
| 异步清理期间提前显示停止，或启动失败后未复位 | 状态在进程回收及服务结束时更新；启动、停止、恢复、连续操作实测 |
| 服务/子进程意外退出可能留下运行时或超时 Shell | 父进程死亡信号、运行时文件锁、kill-on-drop 和退出清理；杀死运行时后恢复、超时进程消失、显式停止不重启实测 |
| 页面保存状态可能与外部启动的运行配置不一致 | 活跃状态同步持久化配置；最终截图确认禁用的能力开关准确显示 |

另检查了：非导出 Service、凭据不落入配置/日志、私有工作区 canonical 路径检查、
导入不覆盖、单文件大小上限、nonce 匹配状态文件、身份切换停止旧服务、
APK 的 nativeLibraryDir 提取方式、上游许可证和 Android 不支持能力的声明。

## 实测结果

- 最终 Debug APK：ARM64 / x86_64 构建通过。ELF 使用 Android linker，LOAD 对齐 16 KB。
- JVM：54 项测试通过，0 失败、0 错误；包括 3 项新增 Portal 回归。
- Android 16 / API 36 / x86_64 模拟器：独立包名 `town.beings.nativeapp.portalqa`，
  真实 APK、前台 Service、Rust 进程和 WebSocket/MCP 执行，11 组通过：
  1. APK 内可执行文件启动、认证握手和状态发布。
  2. initialize、工具发现、status、凭据不出现在 status 中。
  3. 中文文件读写、目录与搜索、路径穿越/符号链接拒绝。
  4. 公网 example.com 的 DNS / HTTPS / 网页获取。
  5. WebSocket 断开后重连并继续服务请求。
  6. 显式停止后进程消失，超过重试间隔不再启动。
  7. 后台命令输出、HTTP 回调、超时 Shell 被回收。
  8. 用户开启 Shell 后执行；运行时被 SIGKILL 后恢复。
  9. portal_restart 产生新进程，工作区保留。
  10. 文件、网页、Shell 和不支持的工具关闭时拒绝直接调用。
  11. 启动后同一主线程轮次立即停止，不残留子进程、不停在 stopping、不触发前台超时。
- 界面截图：连接状态、按钮、设备名称、能力开关与说明可读，无遮挡。
- `git diff --check` 通过。Lint 0 errors、52 warnings，主要为依赖更新、图标、
  KTX 写法与 SharedPreferences 同步写入建议；没有隐藏或抑制检查。

日志与产物保存在被 Git 忽略的 `artifacts/`：`portal-final-build.log`、
`portal-instrumentation.txt`、`portal-qa.png`、`being-portal-debug.apk`，
以及独立 QA 应用和测试 APK。

最终 Debug APK 大小 74,376,361 字节，SHA-256：
`8d30563d8cf4cc0fa8f8b1641791281f8e6a81317f7c28bbf251e286c229dc41`。

## 2026-10-21 真机补充验证

- 用户允许 USB 安装后，恢复 ADB 连接，独立 QA 应用及测试组件安装成功。
- Redmi Note 14 Pro+（24115RA8EC），Android 16 / API 36，`arm64-v8a`：
  上述 11 组端到端测试全部通过，包括公网 HTTPS 获取和快速启动/停止回归。
- 使用此前已验证的 QA APK，未修改生产代码；未覆盖正式 Being 应用及其身份数据。
  测试结束清除 QA 合成连接、停止服务，检查无残留 Portal 运行时进程。
- 日志：`artifacts/portal-device-instrumentation-2026-10-21.txt`；
  截图：`artifacts/portal-device-qa-2026-10-21.png`。

## 验证边界

- ARM64 真机运行验证已完成；厂商后台策略及长时间待机尚未验证。
- 协议使用本地合成凭据与 mock relay；没有向真实 Being 发送测试消息。
  公网 HTTPS 网页获取已验证，但真实 Being 的 WSS relay 联调尚未执行。
- 最低支持 API 28；本轮设备运行验证为 API 36，未覆盖所有 Android 版本。
- 文件工具边界不是 Shell 沙箱；开启 Shell 后具有 App UID 权限。
  任意 Shell 自行创建的后台后代、系统强停、重启与 OEM 省电限制不作持续运行保证。
- 系统文件选择器完整交互、通知点击、拒绝通知权限、锁屏/Doze 长测尚未逐项设备验收。
- 本次完成实现范围的代码 review 与自动化功能验证；上述平台/真实服务验收仍需对应环境。
