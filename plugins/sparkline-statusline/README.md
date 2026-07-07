# sparkline-statusline

Claude Codeのステータスラインにスパークラインゲージでコンテキスト使用率・レートリミットを表示するプラグインです。

## 表示内容

- **PR**: 現在ブランチに紐づく open PR 番号を OSC 8 ハイパーリンクで表示 (Cmd/Ctrl+Click で開く)。`review_state` に応じてアイコン: `✓` approved / `✗` changes_requested / `•` pending / `•` (dim) draft。PR が無い時は非表示。
- **ctx**: コンテキストウィンドウ使用率
- **5h**: 5時間レートリミット使用率（リセット時刻付き）
- **7d**: 7日間レートリミット使用率

### レイアウト

2 行構成: 1 行目はモデル名と PR (識別情報)、2 行目は使用率 (ctx / 5h / 7d)。使用率がどれも取れない時は 1 行目だけになる。

### 出力例

```plain
Claude Opus 4.6 │ ✓ #1234
ctx ▅▆▇█▁▁▁▁ 62% │ 5h ▂▃▁▁▁▁▁▁ 15% (reset 18:30) │ 7d ▁▁▁▁▁▁▁▁ 3%
```

## PR リンクの動作条件

OSC 8 ハイパーリンクは端末依存です:

- ✅ iTerm2 / Kitty / WezTerm / Windows Terminal (最近版) など
- ⚠️ Windows Terminal で下線が付かない場合は `FORCE_HYPERLINK=1 claude` で起動
- ⚠️ tmux 内では [claude-code#27047](https://github.com/anthropics/claude-code/issues/27047) の既知バグで Claude Code 経由の OSC 8 が伝わらない場合あり (回避策は tmux 側 `set -as terminal-features ",*:hyperlinks"`)
- ❌ macOS Terminal.app は非対応 (テキストとして `#1234` は見える)

## 設定方法

プラグインを有効にすると、セッション開始時に `~/.claude/settings.json` の `statusLine` が自動設定されます。手動設定は不要です。

## 参考記事

https://nyosegawa.com/posts/claude-code-statusline-rate-limits/
