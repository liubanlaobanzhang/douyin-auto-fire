#!/usr/bin/env bash
# 把本次运行的失败截图归档到仓库的 screenshots/ 目录并提交推送。
#
# 由 .github/workflows/send.yml 在任务失败时（if: failure()）调用，
# 也可以在本地手动运行，用于整理已有的 artifacts/ 截图。
#
# 用法：
#   bash scripts/archive-screenshots.sh [artifacts 目录]
#
# GitHub Actions 自动提供的环境变量：
#   GITHUB_RUN_ID / GITHUB_RUN_NUMBER / GITHUB_SERVER_URL / GITHUB_REPOSITORY
#   GITHUB_REF_NAME / GITHUB_SHA / GITHUB_EVENT_NAME / GITHUB_WORKFLOW
#
# 可选环境变量：
#   SCREENSHOT_KEEP  保留最近多少次失败记录，默认 30（0 表示不清理）
#   SCREENSHOT_DIR   归档目录，默认 screenshots
#   SCREENSHOT_PUSH  设为 0 时只归档不提交，方便本地调试
#
# 说明：为了兼容 macOS 自带的 bash 3.2，这里只用 POSIX 风格的循环，
# 不使用 mapfile / ${arr[@]} 等需要 bash 4+ 的写法。

set -euo pipefail

ARTIFACTS_DIR="${1:-artifacts}"
KEEP="${SCREENSHOT_KEEP:-30}"
TARGET_ROOT="${SCREENSHOT_DIR:-screenshots}"
PUSH="${SCREENSHOT_PUSH:-1}"

if [ "$KEEP" -gt 0 ] 2>/dev/null; then :; else
  echo "SCREENSHOT_KEEP 必须是数字，当前值: $KEEP" >&2
  exit 2
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if [ ! -d "$ARTIFACTS_DIR" ]; then
  echo "没有 $ARTIFACTS_DIR 目录，本次运行没有截图可归档"
  exit 0
fi

# 单账号模式截图在 artifacts/screenshots/，多账号模式在 artifacts/<账号>/screenshots/，
# 因此按目录层级递归查找，并在归档时把账号名作为文件名前缀。
FOUND_LIST="$WORK_DIR/found.txt"
find "$ARTIFACTS_DIR" -type f -path '*/screenshots/*' \
  \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \) |
  LC_ALL=C sort > "$FOUND_LIST"
FOUND_COUNT="$(wc -l < "$FOUND_LIST" | tr -d ' ')"

if [ "$FOUND_COUNT" -eq 0 ]; then
  echo "本次运行没有生成失败截图，跳过归档"
  exit 0
fi

stamp="$(date -u +%Y%m%d-%H%M%S)"
run_id="${GITHUB_RUN_ID:-local}"
run_dir="$TARGET_ROOT/$stamp-run$run_id"
mkdir -p "$run_dir"

index="$run_dir/README.md"
{
  echo "# 失败截图 $stamp"
  echo
  echo "| 项目 | 值 |"
  echo "| --- | --- |"
  echo "| 工作流 | ${GITHUB_WORKFLOW:-local} |"
  echo "| 运行 | ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-unknown}/actions/runs/$run_id |"
  echo "| 触发方式 | ${GITHUB_EVENT_NAME:-local} |"
  echo "| 分支 | ${GITHUB_REF_NAME:-local} |"
  echo "| 提交 | ${GITHUB_SHA:-local} |"
  echo
  echo "## 截图（$FOUND_COUNT）"
  echo
} > "$index"

while IFS= read -r file; do
  [ -n "$file" ] || continue
  rel="${file#"$ARTIFACTS_DIR"/}"
  name="$(basename "$rel")"
  parent="$(dirname "$rel")"      # screenshots 或 account2/screenshots
  account="$(dirname "$parent")"  # . 或 account2
  if [ "$account" != "." ]; then
    name="$account-$name"
  fi
  cp -f "$file" "$run_dir/$name"
  # 文件名由 app/main.py 生成（只含字母数字、中日韩文字、_ . -），
  # 不含空格与括号，可直接作为 Markdown 图片链接。
  {
    echo "![$name]($name)"
    echo
  } >> "$index"
done < "$FOUND_LIST"

echo "已归档 $FOUND_COUNT 张截图到 $run_dir"

# 只保留最近 $KEEP 次失败记录，避免仓库体积无限增长
if [ "$KEEP" -gt 0 ]; then
  ALL_LIST="$WORK_DIR/runs.txt"
  find "$TARGET_ROOT" -mindepth 1 -maxdepth 1 -type d -name '*-run*' |
    LC_ALL=C sort > "$ALL_LIST"
  TOTAL="$(wc -l < "$ALL_LIST" | tr -d ' ')"
  if [ "$TOTAL" -gt "$KEEP" ]; then
    STALE_LIST="$WORK_DIR/stale.txt"
    awk -v keep="$KEEP" '{ line[NR] = $0 } END { for (i = 1; i <= NR - keep; i++) print line[i] }' \
      "$ALL_LIST" > "$STALE_LIST"
    while IFS= read -r dir; do
      [ -n "$dir" ] || continue
      echo "清理旧的失败记录: $dir"
      rm -rf "$dir"
    done < "$STALE_LIST"
  fi
fi

if [ "$PUSH" != "1" ]; then
  echo "SCREENSHOT_PUSH=$PUSH，已跳过提交推送"
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git add -A -- "$TARGET_ROOT"
if git diff --cached --quiet; then
  echo "screenshots/ 没有变化，无需提交"
  exit 0
fi
git commit -m "chore(screenshots): 归档失败截图 $stamp (run $run_id)"

branch="${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD)}"
for attempt in 1 2 3; do
  if git pull --rebase --autostash origin "$branch" && git push origin "HEAD:refs/heads/$branch"; then
    echo "失败截图已推送到 $branch: $run_dir"
    exit 0
  fi
  echo "第 $attempt 次推送失败，5 秒后重试" >&2
  git rebase --abort >/dev/null 2>&1 || true
  sleep 5
done

echo "截图归档推送失败：请检查仓库 Settings → Actions → General → Workflow permissions" >&2
echo "是否已设为 Read and write permissions（或配置 SCREENSHOTS_TOKEN Secret）。" >&2
echo "截图本身仍可在本次运行的 Artifacts 中下载。" >&2
exit 1
