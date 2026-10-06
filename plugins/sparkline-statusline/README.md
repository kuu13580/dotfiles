# sparkline-statusline

Claude Codeのステータスラインにスパークラインゲージでコンテキスト使用率・レートリミット・prompt cache を表示するプラグインです。Claude Code 専用です (Antigravity 非対応)。

## 表示内容

- **ctx**: コンテキストウィンドウ使用率
- **5h**: 5時間レートリミット使用率（リセット時刻付き）
- **7d**: 7日間レートリミット使用率
- **cache**: prompt cache の状態 (● warm / ○ cold)、cold になる時刻、hit ratio。miss があれば回数と直近の原因

### 出力例

```plain
Claude Opus 4.6 │ ctx ████▇    62% │ 5h █▁       15% (reset 18:30) │ 7d ▁        3% │ cache ● ~14:32 91% ✗2 tools_changed
```

## Desktop app (mod)

同梱の mod (`hooks/register.tsx`) が Desktop app の Code tab でプロンプト上の band に同じ形式で表示します (モデル名は除く)。terminal では描画せず statusline に任せます。

mod は statusline の `prompt_cache` を受け取れないため、cache は表示できる範囲に限ります。

- hit ratio: メインスレッドのターンの usage から計算 (プロセス起動・`/clear`・resume で 0 から)
- ● / ○ と時刻: model 切り替え時に TTL を取得できた場合のみ (切り替え直後は次の応答まで ○)
- miss 回数・原因: 表示しない

## 表示仕様 (statusline.py と register.tsx で揃える)

- ゲージ: 8 文字、` ▁▂▃▄▅▆▇█` の 9 段階
- 色: 50% 未満は `rgb(pct*5.1, 200, 80)`、50% 以上は `rgb(255, 200-(pct-50)*4, 60)`
- 区切り ` │ `、ラベル・補足は dim、時刻は `HH:MM` (ローカル)

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

プラグインを有効にすると、セッション開始時に `~/.claude/settings.json` の `statusLine` が自動設定されます (`refreshInterval: 60` 付き)。手動設定は不要です。

## 参考記事

https://nyosegawa.com/posts/claude-code-statusline-rate-limits/
