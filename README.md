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

在黑苹果的干净工作树准备比直装页已发布版本更新的版本和构建号，例如 `python3 ci/publish-direct-install.py --prepare --version 1.0.25 --build 17`。把输出的 `archive_path` 和 `archive_sha256` 交给 `codex/focus-adhoc-signing` 分支上的 Ad Hoc 签名任务。该分支沿用 `testflight.yml` 作为任务入口，执行的是本机 Ad Hoc 签名导出，产物为 `Focus-AdHoc.ipa`。

准备任务按直装频道和版本、构建号唯一标识。对相同提交和配置重复执行 `--prepare` 时会核对归档 SHA-256 并返回同一个签名输入。如果看到 `signed_ipa`，可直接进入发布。不同源码使用新的版本或构建号。

在同一来源提交用相同版本和构建号运行 `python3 ci/publish-direct-install.py --signed-ipa <签名任务导出的文件> --version 1.0.25 --build 17`。发布前核验主 App 和两个通知扩展的 Ad Hoc 签名、设备范围、推送权限，以及与准备归档一致的二进制 UUID，并从公网回读安装包。校验通过后，固定的「今日 → 更新」入口才会指向新版本。发布后从公网安装页确认显示的新版本和构建号，并区分「已可更新」和「手机已安装」。

发布成功后，直装频道保留正式 IPA。本机在私有的 `~/.local/share/focus-direct-install/receipts/` 中保存含提交、哈希、UUID 和公网确认时间的 `release.json`，以及用于分析崩溃的 `dSYMs.zip`。公网回读和本机记录落盘后，发布器清理这一版的交接归档和签名包副本。若公网已切换且交接目录还在，用原发布命令可复验和继续收尾。临时源码、编译缓存和验证文件随步骤结束清理。发生构建错误时，构建日志单独保存在私有 `diagnostics/`。

同一台 iPhone 已验证 Ad Hoc 构建 17 可直接覆盖到构建 18，原有本地设置文件保留。

本机配置在 `~/.local/share/focus-direct-install/config.json`，由发布主机保管，文件权限为 `0600`。配置包括 HTTPS 公网入口 `public_origin`、静态资源目录 `public_img_root`、固定的随机目录名 `channel`、唯一的设备登记编号 `device_udid` 和签名团队 `team_id`。同一设备的后续构建继续使用同一个 `channel`。直装发布会把该页面地址写入已签名 App 的 `FocusDirectInstallURL`。
