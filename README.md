# AI Server iOS Client

一个使用 SwiftUI 构建的 AI Server 原生 iOS 客户端。首个版本提供多来源新闻流，默认通过
`https://api.wanghengai.xin` 连接阿里云 HTTPS 入口，再经 FRP 私有通道访问 AI Server。

## 当前功能

- X、微博、抖音、B站、知乎、Truth、RSS、老中、YouTube、快讯频道
- 针对社交动态、B站、RSS 的原生信息流布局
- 图片网格、视频入口、评分、标签和新闻详情
- 下拉刷新、滚动分页、频道缓存与选择恢复
- 原文、系统分享、市场、人物和日报入口
- 服务器地址配置与真实连接检测
- 网络失败、空数据和重试状态

## 开始使用

1. 从 App Store 安装并首次启动完整版本的 Xcode，完成许可证与组件安装。
2. 打开 `AIServerClient.xcodeproj`。
3. 选择已配对的 iPhone 或已安装的 iPhone 模拟器并运行。

项目最低支持 iOS 17。

客户端仅接受 HTTPS 服务器地址，并使用系统默认的 App Transport Security 策略。

## iOS 开发与自动构建

本机就是黑苹果开发主机，主工作区为 `/Users/wang/Desktop/ai-server-ios`；其他电脑通过 `ssh hackintosh` 连接。不在 MacBook 旧副本构建 iOS。

禁止运行任何测试。工程不包含 XCTest/UI 测试目标或 scheme 测试动作；验收使用静态检查与无签名编译。`ruby ci/check-no-tests.rb` 静态检查工程和构建入口，流水线在构建、归档前执行这项检查。普通 shell 文件存在性检查保留。

GitHub `main` 是稳定代码源。开始前运行 `./ci/safe-sync.sh main`。安全同步检测到未提交改动会停止；此时使用独立任务工作区，不覆盖开发中的代码。

- GitHub 自托管运行器 `hackintosh-ai-server-ios` 使用 `ios-hackintosh` 标签，负责自动合并和构建。
- `main` 更新后自动同步主工作区，并每 5 分钟检查一次；GitHub Actions 故障接管每分钟检查一次。
- 编译验证无需手机或签名证书。仓库变量 `IOS_DEVICE_INSTALL_ENABLED=false` 暂停自动真机安装，代码仍可验证和发布到 `main`。
- 手动运行 `Build on Hackintosh` 可指定分支或提交，默认仅构建。手机配对、签名配置完成后，才选择 `install_on_device`，并按需开启自动安装变量。
- TestFlight 仍是需要签名凭据的独立发布任务，迁移不会自动上传。

详细约定见 `AGENTS.md`。
