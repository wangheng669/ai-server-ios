# iOS 工程协作规则

GitHub `main` 是两台 Mac 唯一的稳定代码源。主项目目录长期停留在 `main`；每个任务使用 `~/.codex/worktrees/ai_server_ios/<任务名>` 和唯一的 `codex/<任务名>` 分支。

## 统一交付流程

所有任务按治理中心的六个阶段执行：**工作区 → 提交审查 → 排队集成 → 验证 → 发布 → 验收**。

1. 开始前运行 `git status --short`；主工作区干净时运行 `./ci/safe-sync.sh main`。
2. 从最新 `origin/main` 创建独立 worktree/任务分支；已在任务 worktree 时直接继续。修改共享文件前运行 `./ci/check-worktree-overlap.sh <文件或目录>`。
3. 保留无关改动；相关工作区有改动时不得自动拉取、切换、重置、清理或覆盖。禁止强制推送、`git reset --hard`，或用整段 ours/theirs、删功能、跳过测试规避冲突。
4. 完成相关验证后提交任务 worktree 的全部任务文件并推送 `codex/*`。iOS 不使用 PR；推送会进入 `AI merge task branch into main` 串行队列。
5. 合并、验证和发布由中央流程执行；App 变更须完成签名构建和真机安装，非 App 变更可按 `published-no-app-change` 验收。
6. 必须确认任务提交已进入最新 `origin/main`，并在治理中心完成发布和验收后，才可报告完成。
7. 任务创建者在验收结束时删除已合并且干净的任务 worktree/本地分支并清理远端引用；仍在验收或等待用户回复的任务不得由其他任务清理。

判断其他 worktree 是否活跃时，同时检查工作区状态、提交是否进入 `origin/main` 和中央流程结果；仅存在目录或分支不构成阻塞。后台同步只是兜底，不能替代上述确认。

## 中央 Mac 与真机

- `IOS_CENTRAL_RUNNER_LABEL` 选择中央机器：MacBook Air 为 `home-installer`，Mac mini 为 `office-builder`。
- 仅当任务影响 App 构建、测试或安装时，才需要确认电脑名称、Runner 在线状态和 `devicectl` 设备状态。用户当前所在 Mac 能识别目标 iPhone 时，该 Mac 优先作为中央 Mac；当前 Mac 不可识别设备或用户明确要求时才回退另一台机器。
- 正式真机安装只使用已合并的稳定 `main`。用户明确要求验收未合并改动时，可以安装任务分支或提交 SHA，但必须标记为临时测试，不得称为正式发布。
- 构建成功、工作流触发或设备处于 Xcode `Preparing` 都不等于安装成功；必须取得 `devicectl` 安装成功证据。启动被锁屏拒绝时，应分别报告“已安装”和“未启动”。
- GitHub Actions 因基础设施故障失败或无法开始时，运行本地兜底前必须读取治理后台 `GET /api/admin/v1/system/ios-delivery-operations` 返回的 `localCentralAuthorization.enabled`。当该值为 `true` 时，视为用户对本地中央合并的持续明确授权；当该值为 `false`、缺失或接口不可用时，必须在当前对话中取得用户明确授权。无论采用哪种授权，仍须确认当前中央 Mac 能识别目标 iPhone，才可运行 `./ci/local-central-merge.sh --source codex/<任务> --failed-run <run-id> --confirm-infrastructure-failure`。不得跳过测试、签名、并发保护或必要的真机安装。

## 模拟器与共享资源

- 统一复用现有 `iPhone 16e`。只有会改变或读取运行中模拟器状态的操作才需要锁：测试、安装、启动、清理 App 数据和界面操作均通过 `./ci/with-ios-simulator-lock.sh --label <任务名> -- <命令>`。纯编译（包括 generic device build，以及使用独立 DerivedData 且不安装/启动 App 的 `build`、`build-for-testing`）不占模拟器锁。
- 使用 Computer Use、截图、辅助功能树、`idb`、Maestro、`simctl io/ui` 或 Xcode UI 控制 **iOS 模拟器** 时，先用同一标签 `--hold`，再执行 `--assert-held`；普通网页浏览不属于模拟器操作。
- 不得同时启动两个模拟器自动化会话。申请前运行 `--status`；不得抢占有效锁。等待和持锁时限使用脚本默认值，中央排队参数由工作流设置。资源繁忙时释放当前执行轮次并报告持有者；`--hold` 只用于立即进行的交互验收，结束、失败或转去修改代码时立即释放。
- 中央完整测试、模拟器、真机安装、主分支合并和生产发布必须串行。等待共享资源超过 2 分钟时，说明资源、持有者和排队原因；等待期间不得占用模拟器锁。
- 普通任务的构建缓存和临时测试产物仅放在任务 worktree 内已忽略的 `DerivedData/`，不得提交或写入主工作区；`artifacts/` 仅用于人工验收证据，随任务 worktree 在验收后清理。
- 安装增量清理由 `ci/sign-and-install-ios.sh` 自动执行，不得在 Runner 持久配置中关闭；操作细节见 `ci/prune-ios-install-deltas.sh --help`。
- 测试范围由中央流程和 `ci/is-low-risk-ios-diff.sh` 自动判定，不得人工绕过；低风险 App 变更仍须签名构建、真机稳定性检查、安装和发布验收。

## 后端与安全边界

- 后端通过 `ssh mac-x` 使用 `/home/wanngheng/home/ai_server`；修改前读取该仓库的 `AGENTS.md`。不要把 Actions Runner、`_work` 或其他任务 worktree 当作日常修改入口。
- 只有中央 AI 流程可以更新 iOS `main`。被选中的 Runner 必须由已登录 Codex 的本地用户运行；未登录时流程必须安全失败。
