不要任何兼容逻辑

# iOS 开发位置

- 本机就是黑苹果开发主机；其他电脑通过 `ssh hackintosh` 连接。
- 主工作区为 `/Users/wang/Desktop/ai-server-ios`；有未提交改动时使用独立任务工作区，不覆盖、重置或清理他人工作。
- 不在 MacBook 旧副本或 Actions Runner 的 `_work` 中开发、构建。

# 禁止运行测试

- 不运行任何测试，包括 XCTest、UI 测试、脚本回归及 `xcodebuild test`、`test-without-building`、`build-for-testing`。不新增测试目标、测试计划或 scheme 测试动作。
- 验收使用静态检查与无签名 `xcodebuild build`。`ruby ci/check-no-tests.rb` 只读取工程配置和构建入口，不执行测试、构建或模拟器操作。
- 保留编译、签名、archive/export 和发布能力；发布、安装须有对应任务授权。
- 不为排查测试克隆删除模拟器或修改机器安全设置。
- 推送前检查工作流触发条件：`codex/**` 会触发自动合并和设备交付。未经交付授权的修复使用不会触发该流程的 `feature/**` 分支及 PR；优先复用已有修复 PR。

# 验收与直装产物

- 直装发布使用黑苹果上的 `~/.local/bin/focus-direct-install`，显式指定源码提交、版本和构建号。统一入口从 `main` 读取发布程序，并根据交接记录续跑同一构建。公网回读成功并保存发布记录和崩溃符号后，由发布程序清理本次交接的完整归档和 IPA 副本。
- 验收构建使用本任务的临时目录存放 `DerivedData` 和中间产物。收尾时只清理本任务已结束的临时产物，保留源码、发布归档和签名包。
- `.artifacts` 保留验收摘要、必要的截图和原始证据，并记录来源提交或构建号。

# 后端与安全边界

- AI Server 在本机 macOS 原生运行，主仓库为 `/Users/wang/Desktop/ai_server`，程序与持久数据位于 `/Users/wang/.local/share/ai-server`。
- 修改后端前读取其 `AGENTS.md` 并按要求建立独立任务工作区；不提交本机凭据。
