# sparkline-statusline

Claude Codeのステータスラインにスパークラインゲージでコンテキスト使用率・レートリミットを表示するプラグインです。

## 表示内容

- **ctx**: コンテキストウィンドウ使用率
- **5h**: 5時間レートリミット使用率（リセット時刻付き）
- **7d**: 7日間レートリミット使用率

### 出力例

```plain
Claude Opus 4.6 │ ctx ▅▆▇█▁▁▁▁ 62% │ 5h ▂▃▁▁▁▁▁▁ 15% (reset 18:30) │ 7d ▁▁▁▁▁▁▁▁ 3%
```

## PR 番号を clickable にしたい場合

PR 番号のリンク表示は本プラグインではなく **Claude Code 標準の footer PR バッジ**が担当します (statusline の1つ下に自動表示)。対応端末では OSC 8 で clickable になります。

Windows Terminal などで下線が出ず clickable にならない場合は、Claude Code の terminal auto-detection をバイパスする `FORCE_HYPERLINK` を設定してから起動します:

```bash
FORCE_HYPERLINK=1 claude
```

PowerShell の場合:

```powershell
$env:FORCE_HYPERLINK = "1"; claude
```

詳細: [Claude Code Docs — Customize your status line (Troubleshooting)](https://code.claude.com/docs/en/statusline)

## 設定方法

プラグインを有効にすると、セッション開始時に `~/.claude/settings.json` の `statusLine` が自動設定されます。手動設定は不要です。

## 参考記事

https://nyosegawa.com/posts/claude-code-statusline-rate-limits/
