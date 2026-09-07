# iOS 工程协作规则

GitHub `main` 是两台 Mac 唯一的稳定代码源。主项目目录长期停留在 `main`；每个任务使用 `~/.codex/worktrees/ai_server_ios/<任务名>` 和唯一的 `codex/<任务名>` 分支。

## 统一交付流程

产生仓库改动的任务按治理中心的六个阶段执行；只读分析无需同步、创建 worktree 或发布：**工作区 → 提交审查 → 排队集成 → 验证 → 发布 → 验收**。

1. 开始前运行 `git status --short`；新建修改任务时，仅在干净的主工作区运行 `./ci/safe-sync.sh main`。已在任务 worktree 时直接继续，不运行切换到 main 的同步命令。
2. 从最新 `origin/main` 创建独立 worktree/任务分支；已在任务 worktree 时直接继续。修改共享文件前运行 `./ci/check-worktree-overlap.sh <文件或目录>`；结果仅提示本机文件重叠，检查实际改动后协调冲突，不因文件同名自动阻塞。
3. 保留无关改动；相关工作区有改动时不得自动拉取、切换、重置、清理或覆盖。禁止强制推送、`git reset --hard`，或用整段 ours/theirs、删功能、跳过测试规避冲突。
4. 完成相关验证后提交任务 worktree 的全部任务文件并推送 `codex/*`。iOS 不使用 PR；推送会进入 `AI merge task branch into main` 串行队列。
5. 合并、验证和发布由中央流程执行；App 变更须完成签名构建和真机安装，非 App 变更可按 `published-no-app-change` 验收。
6. 必须确认任务提交已进入最新 `origin/main`，并在治理中心完成发布和验收后，才可报告完成。
7. 任务创建者完成验收且不再等待用户回复时，在主工作区运行 `./ci/finish-task.sh --source codex/<任务> --release`，统一清理已合并且干净的任务 worktree、本地分支和远端引用。后台同步和中央发布不清理任务。

治理中心 `acceptance=accepted` 表示自动交付检查通过，不代表功能验收或用户确认。涉及功能或交互的变更，还须记录对应测试或界面验证证据；用户要求亲自验收时等待其回复。任务完成前须核对提交与对应交付记录，不以目录是否存在判断任务活跃。

## 中央 Mac 与真机

- `IOS_CENTRAL_RUNNER_LABEL` 选择中央机器：MacBook Air 为 `home-installer`，Mac mini 为 `office-builder`。
- 仅当任务影响 App 构建、测试或安装时，才需要确认电脑名称、Runner 在线状态和 `devicectl` 设备状态。用户当前所在 Mac 能识别目标 iPhone 时，该 Mac 优先作为中央 Mac；当前 Mac 不可识别设备或用户明确要求时才回退另一台机器。
- 正式真机安装只使用已合并的稳定 `main`。用户明确要求验收未合并改动时，可以安装任务分支或提交 SHA，但必须标记为临时测试，不得称为正式发布。
- 构建成功、工作流触发或设备处于 Xcode `Preparing` 都不等于安装成功；必须取得 `devicectl` 安装成功证据。启动被锁屏拒绝时，应分别报告“已安装”和“未启动”。
- GitHub Actions 因基础设施故障失败或无法开始时，运行本地兜底前必须读取治理后台 `GET /api/admin/v1/system/ios-delivery-operations` 返回的 `localCentralAuthorization.enabled`。当该值为 `true` 时，视为用户对本地中央合并的持续明确授权；当该值为 `false`、缺失或接口不可用时，必须在当前对话中取得用户明确授权。无论采用哪种授权，仍须确认当前中央 Mac 能识别目标 iPhone，才可运行 `./ci/local-central-merge.sh --source codex/<任务> --failed-run <run-id> --confirm-infrastructure-failure`。不得跳过测试、签名、并发保护或必要的真机安装。

## 模拟器与共享资源

- 复用 `iPhone 16e`；模拟器测试、安装、启动、数据清理和界面操作统一通过 `./ci/with-ios-simulator-lock.sh --label <任务名> -- <命令>`。交互验收用同一标签先 `--hold`、再 `--assert-held`，结束或转去修改代码时立即释放。
- 不抢占有效锁；同一真机安装互斥，集成发布使用中央串行队列。独立检查和使用独立 DerivedData 的纯编译可并行。
- Xcode 构建缓存使用任务 worktree 内已忽略的 `DerivedData/`；其他临时产物放已忽略目录或系统临时目录，不得提交或污染主工作区。

## 后端与安全边界

- 后端通过 `ssh mac-x` 使用 `/home/wanngheng/home/ai_server`；修改前读取该仓库的 `AGENTS.md`。不要把 Actions Runner、`_work` 或其他任务 worktree 当作日常修改入口。
- 只有中央 AI 流程可以更新 iOS `main`。Runner 使用本地用户运行；需要调用 Codex 时必须检查登录状态，未登录则安全失败。
