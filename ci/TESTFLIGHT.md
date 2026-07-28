# TestFlight 发布配置

仓库提供工作流 `Upload iOS app to TestFlight`。它会在 Mac mini 的 `office-builder` 上运行测试、生成 Release Archive，并上传到 App Store Connect。

工作流每天北京时间 04:30 自动检查 `main`。仅当 `main` 相比上一次成功发布出现新提交时才启动构建和上传；没有新提交时会快速结束。也可以从 GitHub Actions 手动运行，手动运行始终会执行上传。Mac mini 离线时，任务会排队等待 `office-builder` 上线。

上传完成后，工作流会继续查询 App Store Connect，直到新构建状态变为 `VALID`（界面显示“完成”）或处理失败。进入终态后，它会使用 `IOS_DEPLOYMENT_STATUS_API_KEY` 调用 AI Server 的受鉴权接口，由服务端现有企业钉钉机器人发送版本号、Build Number、完成时间和发布任务链接。默认最多等待 30 分钟。

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

构建使用自托管 Runner，不消耗 GitHub 托管 macOS 构建机额度。电脑、电力、网络和 Apple Developer Program 会员费用仍由开发者承担。
