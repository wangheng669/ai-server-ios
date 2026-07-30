# 两台 Mac 的 Codex 协作规则

GitHub `main` 是两台 Mac 唯一的稳定代码源。主项目目录长期停留在 `main`；开发使用 `~/.codex/worktrees` 下的独立 worktree 和唯一的 `codex/<任务名>` 分支。Mac mini 的中央 AI 流程串行合并、测试；真机安装优先使用用户当前所在且已连接目标 iPhone 的 Mac。

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

## 完成、同步与清理

可用改动通过相关验证后，除非用户明确要求仅保留本地，否则必须：

1. 检查改动并提交任务工作区的全部内容，包括未跟踪文件；禁止直接提交或推送 `main`。
2. 推送 `codex/*` 任务分支，等待 `AI merge task branch into main` 完成。中央流程必须语义化解决冲突并通过完整测试后才能更新 `main`。
3. 确认任务提交已进入 `origin/main`；失败时停止并说明冲突或测试错误。
4. 工作区干净、分支已合并且对应任务已结束后，可同步主项目并删除任务 worktree 和本地分支。不得清理仍在验收或回复中的任务，也不得强制同步另一台存在改动的电脑。

后台同步会在 Mac 在线且工作区安全时快进 `main`、清理已合并任务；它只是兜底，不能替代上述确认。

## 真机与模拟器

- “安装到真机”默认安装最新稳定 `main`。有未提交改动时先完成上述合并流程。
- 真机安装默认使用用户当前所在且已连接目标 iPhone 的 Mac：当前会话运行在 MacBook Air 时直接用 MacBook Air，本人在 Mac mini 时直接用 Mac mini，不跨机器绕行。先测试，再本地构建、签名并用 `devicectl` 安装。设备处于 Xcode `Preparing` 时应等待并重试，不要把构建成功或回退任务已触发当作安装成功。
- 当前 Mac 无法识别目标 iPhone、签名无效或本地直装失败时，才触发 `Build on Mac mini and install on iPhone` 作为回退；`git_ref` 使用 `main`，并等待安装命令成功。临时测试未合并分支时使用该分支或提交 SHA，不改动 `main`。
- 模拟器统一复用现有 `iPhone 16e`。测试、安装、启动或界面操作必须通过 `./ci/with-ios-simulator-lock.sh --label <任务名> -- <命令>`；交互验收先用同一脚本的 `--hold` 独占，完成后立即停止持锁进程。不得绕过锁，也不要无故创建或切换设备。
- 真机只安装已合并的稳定 `main`；多个任务连续合并时以最后一次累计全部改动的安装结果为准。

## 安全边界

- 禁止强制推送、`git reset --hard`、覆盖其他任务，或用整段 ours/theirs、删功能、跳过测试来规避冲突。
- 只有中央 AI 流程可以更新 `main`；`main` 更新会触发真机安装。
- `office-builder` 必须由已登录 Codex 的本地用户运行；未登录时工作流应安全失败且不得更新 `main`。
