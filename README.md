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

## 两台 Mac 协作

仓库使用 GitHub `main` 作为 Mac mini 与 MacBook Air 之间的稳定代码源。日常任务默认直接在 `main` 开发，只有大型、实验性或高冲突风险的任务才使用临时分支。

- 开始新任务时：工作区干净的情况下运行 `./ci/safe-sync.sh main`。
- 提交并同步：提交改动，安全整合远端的新提交，再推送 `main`。
- 安装到真机：推送 `main` 后，Mac mini 自动构建，MacBook Air 自动签名并安装；没有新提交时也可以手动重新安装 `main`。
- 临时测试分支：在 GitHub Actions 手动运行 `Build on Mac mini and install on iPhone`，并填写分支名或提交 SHA。

详细的 Codex 自动协作约定见 `AGENTS.md`。安全同步脚本检测到未提交改动时会直接停止，不会覆盖正在开发的代码。
