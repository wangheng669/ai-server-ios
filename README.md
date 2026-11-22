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

## iPhone 直装发布

焦点改动完成并验证通过后，直接把新版本发到 App 内的「今日 → 更新」。点「更新」后由 iOS 确认并安装，不打开浏览器。日常交付使用 Ad Hoc 直装，无需提交 TestFlight。

在黑苹果上，先在开发工作区提交要交付的改动，再用本机统一入口指定这次发布的源码提交、版本和构建号。

```sh
~/.local/bin/focus-direct-install --release --source-commit "$(git rev-parse HEAD)" --version 1.0.115 --build 107
```

工具每次从 GitHub `main` 读取发布程序，并且只从指定提交导出 Xcode 工程、App、配置和两个通知扩展。发布主机上的入口文件使用 `main` 的 `ci/focus-direct-install.sh`，以 `0700` 权限安装到 `~/.local/bin/focus-direct-install`。Xcode 配置覆盖文件及设备 SDK 在归档前核对。

`--release` 按顺序准备归档、等待 `main` 的 `Sign Focus Ad Hoc` 工作流签名，再验签和发布。准备、签名和发布共用一份含源码提交、版本、构建号和归档 SHA-256 的记录。同一构建中断后重跑原命令，工具会复用已核验的归档、签名任务或 IPA。只准备归档用 `--prepare`，用现有签名包重试发布可用 `--publish`。不同源码使用新的版本或构建号。

发布前核验主 App 和两个通知扩展的 Ad Hoc 签名、登记设备、推送权限和二进制 UUID，并从公网回读安装包。固定的「今日 → 更新」入口切换后继续回读版本号和构建号。手机安装是独立的验收步骤。

发布成功后，直装频道保留正式 IPA。本机在私有的 `~/.local/share/focus-direct-install/receipts/` 中保存 `release.json` 和压缩崩溃符号 `dSYMs.zip`。公网回读和本机记录落盘后，发布器回收本次交接归档和 IPA 副本。每个阶段结束清理临时文件并输出临时目录占用和磁盘可用空间变化。失败时在私有 `diagnostics/` 中保存归档或签名日志的末尾，并保留可续跑的交接记录。异常退出后遗留超过 24 小时的临时目录会在下次发布流程启动时检查，确认闲置后回收。

同一台 iPhone 已验证 Ad Hoc 构建 17 可直接覆盖到构建 18，原有本地设置文件保留。

本机配置在 `~/.local/share/focus-direct-install/release-config.json`，由发布主机保管，文件权限为 `0600`。配置包括 HTTPS 公网入口 `public_origin`、静态资源目录 `public_img_root`、固定的随机目录名 `channel`、唯一的设备登记编号 `device_udid` 和签名团队 `team_id`。同一设备的后续构建继续使用同一个 `channel`。直装发布会把该页面地址写入已签名 App 的 `FocusDirectInstallURL`。
