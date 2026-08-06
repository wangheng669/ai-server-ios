# 两台 Mac 的 Codex 协作规则

GitHub `main` 是两台 Mac 唯一的稳定代码源。主项目目录长期停留在 `main`；开发使用 `~/.codex/worktrees` 下的独立 worktree 和唯一的 `codex/<任务名>` 分支。中央 AI 流程串行合并、测试，并由仓库变量 `IOS_CENTRAL_RUNNER_LABEL` 选择当前中央机器：MacBook Air 使用 `home-installer`，Mac mini 使用 `office-builder`。当前会话运行在 MacBook Air，且用户明确说明目标 iPhone 就在身边、该设备能被当前电脑识别时，MacBook Air 即为本任务的中央 Mac，优先级高于此前配置的 Mac mini。真机安装使用同一台中央 Mac。

## AI Server 后端

- 使用 `ssh mac-x`；主项目为 `/home/wanngheng/home/ai_server`，仓库为 `wangheng669/ai_server`。
- 修改后端接口、静态资源或部署前，先检查该项目的 `AGENTS.md`、工作区状态和部署约定。
- 不要把 Actions Runner、其 `_work` 目录或 `~/.codex/worktrees` 副本当作日常修改入口。

## 开始任务

1. 运行 `git status --short`。
2. 主项目工作区干净时运行 `./ci/safe-sync.sh main`。
3. 从最新 `main` 创建 `~/.codex/worktrees/ai_server_ios/<任务名>` 和唯一的 `codex/<任务名>` 分支；不要在主项目切任务分支。已在任务 worktree 时直接继续。
4. 任何相关工作区有改动都视为未完成任务：不得自动拉取、切换、重置、清理或覆盖。
5. 修改共享页面前运行 `./ci/check-worktree-overlap.sh <文件或目录>`；检测到其他活跃任务修改同一文件时，必须协调顺序或等待合并后再继续。
6. 两台 Mac 尽量修改不同模块，不共用任务分支；必要时在分支名加入机器名。
7. 开始前确认当前电脑名称，并用 `devicectl` 确认目标真机状态。会话运行在 MacBook Air、用户明确说明目标 iPhone 就在身边，且真机显示为 `available (paired)` 或 `connected` 时，必须把当前 MacBook Air 视为中央 Mac：在推送任务分支前将 `IOS_CENTRAL_RUNNER_LABEL` 设为 `home-installer`，确认该 Runner 在线，并把中央合并、完整测试和真机安装都留在当前电脑。用户当前在 Mac mini 时再设为 `office-builder`。只有当前电脑无法识别目标 iPhone，或用户明确要求回退时，才能跨机器等待、合并或安装。

## 完成、同步与清理

可用改动通过相关验证后，除非用户明确要求仅保留本地，否则必须：

1. 检查改动并提交任务工作区的全部内容，包括未跟踪文件；禁止直接提交或推送 `main`。
2. 推送 `codex/*` 任务分支，等待 `AI merge task branch into main` 完成。中央流程必须语义化解决冲突并通过完整测试后才能更新 `main`。只有对应 GitHub Actions 已因基础设施故障失败，或因基础设施阻塞无法开始而被明确取消，并且用户明确授权应急合并、当前中央 Mac 能识别目标 iPhone 时，才可在该中央 Mac 运行 `./ci/local-central-merge.sh --source codex/<任务> --failed-run <run-id> --confirm-infrastructure-failure`；该脚本的完整测试、签名构建、`origin/main` 并发保护和真机安装均不得跳过。
3. 确认任务提交已进入 `origin/main`；失败时停止并说明冲突或测试错误。
4. 判断其他 worktree 或 `codex/*` 分支是否仍为活跃任务时，必须同时检查工作区状态、提交是否已进入 `origin/main`，以及对应 PR/中央合并流程是否已完成；不得仅凭 worktree 或分支存在就认定仍在修改或存在冲突。工作区干净、提交已进入 `origin/main` 且合并流程已完成的任务视为待清理遗留项，不作为活跃冲突阻塞新任务；但仍在验收或等待用户回复时不得由其他任务擅自清理。
5. 任务创建者完成合并、部署和验收并准备最终回复时，除非用户明确要求保留本地任务环境，否则必须删除对应任务 worktree 和本地分支，并运行远端引用清理，避免后续 AI 误判。主项目或另一台电脑存在未提交改动时，不得为清理任务而强制同步、切换、重置或覆盖，只清理已确认合并且工作区干净的独立任务 worktree。

后台同步会在 Mac 在线且工作区安全时快进 `main`、清理已合并任务；它只是兜底，不能替代上述确认。

## 真机与模拟器

- “安装到真机”默认安装最新稳定 `main`。有未提交改动时先完成上述合并流程。
- 真机安装默认使用用户当前所在且已连接目标 iPhone 的 Mac：当前会话运行在 MacBook Air 时直接用 MacBook Air，本人在 Mac mini 时直接用 Mac mini，不跨机器绕行。先测试，再本地构建、签名并用 `devicectl` 安装。设备处于 Xcode `Preparing` 时应等待并重试，不要把构建成功或回退任务已触发当作安装成功。
- 当前 Mac 无法识别目标 iPhone、签名无效或本地直装失败时，先报告本机安装未完成；只有用户明确要求使用 Mac mini 回退时，才触发 `Build on Mac mini and install on iPhone`，`git_ref` 使用 `main`，并等待安装命令成功。临时测试未合并分支时使用该分支或提交 SHA，不改动 `main`。
- 模拟器统一复用现有 `iPhone 16e`。测试、安装、启动或界面操作必须通过 `./ci/with-ios-simulator-lock.sh --label <任务名> -- <命令>`；交互验收先用同一脚本的 `--hold` 独占，完成后立即停止持锁进程。不得绕过锁，也不要无故创建或切换设备。
- Codex 的 Computer Use、浏览器界面控制、截图、辅助功能树读取，以及直接使用 `idb`、Maestro、`simctl io/ui` 或 Xcode UI，全部视为模拟器操作。调用这些非子进程式工具前必须先用 `--hold` 持锁，再用相同 `--label` 执行 `--assert-held`；未持锁、标签不匹配或 `--status` 报告 unmanaged automation 时不得继续。常驻 `idb_companion` 本身不算占用，但任何通过它发起的界面会话都必须持锁。
- 不得同时启动两个自动化会话，即使它们来自同一个任务或 AI。锁脚本会拒绝与未通过锁启动的 `xcodebuild test`、Maestro、idb UI/XCTest、Appium、WebDriverAgent 等进程并行；发现此类进程时应停止或等待，不得绕过检测。
- 真机只安装已合并的稳定 `main`；多个任务连续合并时以最后一次累计全部改动的安装结果为准。

## 多任务并行与共享资源调度

- 多个任务可以并行分析、修改不同文件和执行不占用共享设备的测试；模拟器、中央完整测试、真机安装、主分支合并和生产部署必须串行。
- 等待其他分支合并、CI、部署或模拟器时，不得继续占用模拟器锁，也不得通过循环等待维持无效运行状态。完成可独立进行的工作后，应明确报告等待对象并结束当前执行轮次。
- `--hold` 仅用于正在进行的模拟器交互、截图或界面验收。持锁后必须立即验收；不得在持锁期间分析或修改代码、查询网络、等待 CI 或处理其他任务。
- 交互锁默认最多持有 10 分钟，脚本到时自动释放；确有需要可用 `--hold-seconds` 指定 30–900 秒。验收完成、失败、被阻塞或转去修改代码时必须提前停止持锁进程。
- 中央合并完整测试的优先级高于普通界面验收。发现中央测试正在排队等待模拟器时，普通任务应完成当前不可中断的操作后立即释放，不得开始新一轮验收。
- 申请模拟器前先运行 `./ci/with-ios-simulator-lock.sh --status` 查看持锁标签、进程、模式和到期时间。不得抢占有效锁；只有持锁进程不存在时才允许脚本自动回收遗留锁。
- 等待共享资源超过 2 分钟时，应报告资源名称、当前持有者和排队原因。不得把等待状态笼统描述为仍在测试或处理中。
- 同一文件或目录存在其他活跃任务修改时，完成不冲突的调查后应等待其合并，不得长期轮询，也不得重复触发工作流抢占中央任务。
- 纯构建缓存、DerivedData 和临时测试产物不得纳入 Git 状态。产生缓存的任务负责把它们放在已忽略或工作区外的目录中，不得让缓存变动阻塞其他任务同步。

## 安全边界

- 禁止强制推送、`git reset --hard`、覆盖其他任务，或用整段 ours/theirs、删功能、跳过测试来规避冲突。
- 只有中央 AI 流程可以更新 `main`；GitHub Actions 是默认入口，满足上述严格门禁时本机中央应急脚本是唯一回退入口。`main` 更新后必须完成真机安装。
- 被 `IOS_CENTRAL_RUNNER_LABEL` 选中的 Runner 必须由已登录 Codex 的本地用户运行；未登录时工作流应安全失败且不得更新 `main`。
