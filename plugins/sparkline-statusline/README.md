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

## 設定方法

プラグインを有効にすると、セッション開始時に `~/.claude/settings.json` の `statusLine` が自動設定されます。手動設定は不要です。

## 参考記事

https://nyosegawa.com/posts/claude-code-statusline-rate-limits/
