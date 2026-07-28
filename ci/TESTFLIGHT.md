# TestFlight 发布配置

仓库提供工作流 `Upload iOS app to TestFlight`。它会在 GitHub 托管的 macOS 构建机上运行测试、生成 Release Archive，并上传到 App Store Connect，不依赖开发用 Mac 在线。

工作流每天北京时间 04:30 自动检查 `main`。仅当 `main` 相比上一次成功发布出现新提交时才启动 macOS 构建和上传；没有新提交时只运行短暂的 Linux 检查任务。也可以从 GitHub Actions 手动运行，手动运行始终会执行上传。

## App Store Connect

创建与 `com.wangheng.aiserverclient` 对应的 iOS App，并在“用户和访问 / 集成 / App Store Connect API”中创建团队 API Key。该 Key 需要有管理应用版本、签名和上传构建所需的权限。

## GitHub Actions secrets

- `APP_STORE_CONNECT_KEY_ID`：API Key ID
- `APP_STORE_CONNECT_ISSUER_ID`：Issuer ID
- `APP_STORE_CONNECT_PRIVATE_KEY_BASE64`：`.p8` 私钥文件的 Base64 内容

在 macOS 上可用以下命令复制第三项的值：

```sh
base64 -i AuthKey_KEYID.p8 | pbcopy
```

## 上传

在 GitHub Actions 中手动运行 `Upload iOS app to TestFlight`。默认上传 `main`，也可以输入任务分支、标签或提交 SHA。上传成功后，等待 App Store Connect 处理构建，再在 TestFlight 中完成测试信息和外部测试审核。

## 费用

仓库为私有仓库时，GitHub 托管构建机会消耗仓库所有者套餐内含的 Actions 额度，超出额度后按 GitHub 当时公布的费率计费。标准 macOS 构建机的单价高于 Linux；可在 GitHub 的 Billing & licensing 页面设置 Actions 预算和查看实际用量。公开仓库使用标准 GitHub 托管构建机不计费。
