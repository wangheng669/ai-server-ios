#!/usr/bin/env bash
set -euo pipefail
script_root=$(cd "$(dirname "$0")" && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/ios-task-lifecycle.XXXXXX")
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin"
cat > "$test_root/bin/curl" <<'CURL'
#!/usr/bin/env bash
cat "$IOS_TEST_OPERATIONS"
CURL
chmod +x "$test_root/bin/curl"
export PATH="$test_root/bin:$PATH"
export IOS_TEST_OPERATIONS="$test_root/operations.json"
git init --bare -q "$test_root/remote.git"
git init -q -b main "$test_root/main"
cd "$test_root/main"
git config user.name Test
git config user.email test@example.invalid
git remote add origin "$test_root/remote.git"
echo base > shared.txt
git add shared.txt
git commit -qm base
git push -qu origin main
git worktree add -qb codex/test "$test_root/task"
echo changed > "$test_root/task/shared.txt"
git -C "$test_root/task" commit -qam task
git -C "$test_root/task" push -qu origin codex/test
sha=$(git -C "$test_root/task" rev-parse HEAD)
# Overlap is advisory even for a committed, unmerged change.
bash "$script_root/check-worktree-overlap.sh" shared.txt
expect_refusal() {
  if bash "$script_root/finish-task.sh" --source codex/test "$@"; then
    echo 'Unsafe task cleanup unexpectedly succeeded.' >&2; exit 1
  fi
  [[ -d "$test_root/task" ]]
  git show-ref --verify --quiet refs/heads/codex/test
  [[ -n "$(git ls-remote --heads origin refs/heads/codex/test)" ]]
}
expect_refusal --release
git merge -q --no-edit codex/test
git push -q origin main
printf '{"data":{"deployment":{"commit":"%s","sourceBranch":"codex/test","phase":"succeeded","acceptance":"accepted"}}}' "$sha" > "$IOS_TEST_OPERATIONS"
expect_refusal
# Sync must retain a merged task, its branch, and its remote ref.
mkdir -p ci
cp "$script_root/automatic-main-sync.sh" "$script_root/git-fetch-origin.sh" ci/
printf "ci/\n" >> .git/info/exclude
bash ci/automatic-main-sync.sh
[[ -d "$test_root/task" ]]
echo untracked > "$test_root/task/untracked"
expect_refusal --release
rm "$test_root/task/untracked"
cp "$IOS_TEST_OPERATIONS" "$test_root/accepted.json"
printf '{"data":{"deployment":{"acceptance":"pending-install"}}}' > "$IOS_TEST_OPERATIONS"
expect_refusal --release
cp "$test_root/accepted.json" "$IOS_TEST_OPERATIONS"
# A newer remote commit must not be deleted by an older task release.
git clone -q --branch codex/test "$test_root/remote.git" "$test_root/newer"
git -C "$test_root/newer" config user.name Test
git -C "$test_root/newer" config user.email test@example.invalid
echo newer > "$test_root/newer/new.txt"
git -C "$test_root/newer" add new.txt
git -C "$test_root/newer" commit -qm newer
git -C "$test_root/newer" push -q origin codex/test
expect_refusal --release
# Reconcile the newer commit, then use a delivery record for that exact commit.
git -C "$test_root/task" fetch -q origin codex/test
git -C "$test_root/task" merge -q --ff-only FETCH_HEAD
git merge -q --no-edit codex/test
git push -q origin main
sha=$(git rev-parse codex/test)
jq --arg sha "$sha" '.data.deployment.commit=$sha' "$test_root/accepted.json" > "$IOS_TEST_OPERATIONS"
bash "$script_root/finish-task.sh" --source codex/test --release
[[ ! -d "$test_root/task" ]]
if git show-ref --verify --quiet refs/heads/codex/test; then
  echo "Released local branch still exists." >&2; exit 1
fi
[[ -z "$(git ls-remote --heads origin refs/heads/codex/test)" ]]
echo 'Task lifecycle checks passed.'
