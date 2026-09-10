# screenshots

本目录用于存放 **GitHub Actions 运行失败时的截图**，由 `.github/workflows/send.yml` 在失败后自动写入并提交，方便直接在仓库里查看失败现场，不需要再去下载 Artifacts。

## 目录结构

```text
screenshots/
  20250101-120000-run1234567890/
    README.md                              本次运行的失败信息（工作流、运行链接、分支、提交）
    20250101-115959-login-3f9a1c.png       单账号模式：登录检查失败截图
    account2-20250101-115959-3f9a1c.png    多账号模式：文件名带账号前缀
```

## 保留策略

- Workflow 中通过 `SCREENSHOT_KEEP=30` 控制，**只保留最近 30 次失败记录**，更早的目录会在归档时自动删除。
- 想要调整数量，修改 `.github/workflows/send.yml` 中 `Archive failure screenshots to repository` 步骤的 `SCREENSHOT_KEEP` 即可；设为 `0` 表示不清理。
- 除本目录外，失败运行的完整诊断文件（`run.log`、`result.json`、`screenshots/`、`traces/`）仍会上传为 Artifacts，默认保留 3 天。

## 手动整理

本地已有 `artifacts/` 时，可以手动归档（不提交，只归档）：

```bash
SCREENSHOT_PUSH=0 bash scripts/archive-screenshots.sh
```

## 关闭该功能

如果不想让失败截图进入仓库，删除 `.github/workflows/send.yml` 中的 `Archive failure screenshots to repository` 步骤即可，同时可把 job 的 `permissions` 改回 `contents: read`。

> ⚠️ 截图可能包含聊天内容、好友昵称等隐私信息。把仓库设为公开前，请先删除本目录下的历史记录，并注意它们已经存在于 git 历史中。
