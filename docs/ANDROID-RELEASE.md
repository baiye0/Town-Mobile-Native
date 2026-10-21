# Android 正式发布

`Android APK` 工作流提供临时 Debug 构建；`Android Release` 工作流发布固定签名的正式 APK 到 GitHub Releases。两者都不会连接或安装到手机。

## 发布版本

1. 修改 `android/version.properties`：`versionName` 使用 `MAJOR.MINOR.PATCH`，`versionCode` 必须比已发布版本大。首版为 `0.1.0` / `2`。
2. 添加 `docs/releases/v版本号.md` 发布说明，完成 review 后提交到 `codex/native-mobile` 并推送。
3. 在该提交创建并推送标签，例如首版：

   ```sh
   git tag -a v0.1.0 -m "Being Android v0.1.0"
   git push origin v0.1.0
   ```

CI 核对标签、版本递增和发布说明，构建固定子模块中的双 ABI Portal，运行 Release 单元测试和 Lint，再构建签名 APK。发布前校验签名证书、应用 ID、版本、不可调试标志、ZIP / ELF 的 16 KB 对齐和 SHA-256。只有构建成功后，独立的发布任务才获得 `contents: write` 权限。

产物包括 APK、SHA-256、构建元数据和签名/包信息。CI 先创建草稿，上传完成后再公开 Release。失败时在 Actions 重跑任务即可继续未完成草稿；已公开 Release 不会被覆盖。手动触发工作流时必须选择版本标签，选择分支不会发布。不要移动已发布的标签，修改应使用新版本。

## 固定签名

以下仓库 Actions Secrets 必须配置，缺失时 CI 失败，不回退到 Debug 签名：

- `ANDROID_RELEASE_KEYSTORE_BASE64`：JKS 文件的 Base64。
- `ANDROID_RELEASE_STORE_PASSWORD`：密钥库密码。
- `ANDROID_RELEASE_KEY_ALIAS`：签名密钥别名。
- `ANDROID_RELEASE_KEY_PASSWORD`：签名密钥密码。

`android/release-certificate.sha256` 是公开证书指纹，CI 用它验证最终 APK，防止误用其他密钥。私钥仅在构建时恢复到 runner 临时目录，构建结束后清理；不会进入 Git、缓存、Artifacts 或 Release。签名私钥和密码应另行安全备份，后续版本必须使用相同密钥。

本次初始化的本机备份位于 `%USERPROFILE%\.android\being-release\`（仅当前用户和 SYSTEM 可访问）。不要把这个目录提交到仓库。

正式版签名与本地/CI Debug 包不同，不能直接覆盖这些测试包。仓库目前为私有，Release 下载需要有访问权限的 GitHub 登录；应用当前使用匿名 GitHub API 检查更新，因此无法读取私有 Release。发布流程不会更改仓库可见性。
