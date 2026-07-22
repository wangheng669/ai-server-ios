# TestFlight 发布配置

仓库提供手动工作流 `Upload iOS app to TestFlight`。它会在 Mac mini 上运行测试、生成 Release Archive，并上传到 App Store Connect。

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
