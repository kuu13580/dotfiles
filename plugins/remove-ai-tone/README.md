# remove-ai-tone

抽象的・演出的な AI 特有のトーンを排し、具体的で直接伝わる日本語で出力させる Claude Code 向け出力スタイル (output style) プラグイン。

短文や対句、不要な否定・留保からの書き出し、主語・対象の省略といった表現を避け、対象・条件・動作を明記した直接的な文章を出力させる。スタイル定義の詳細は [output-styles/remove-ai-tone.md](output-styles/remove-ai-tone.md) を参照。

## 使い方

Claude Code の出力スタイルとして `Remove AI Tone` を指定する。

### コマンドで切り替える

```bash
# 対話形式でスタイルを選択
/output-style

# Remove AI Tone を直接指定
/output-style Remove AI Tone
```

### 設定ファイルで永続化する

プロジェクト単位 (`.claude/settings.local.json`) またはグローバル (`~/.claude/settings.json`) に設定する:

```json
{
  "outputStyle": "Remove AI Tone"
}
```

### 起動時オプションで指定する

```bash
claude --settings '{"outputStyle":"Remove AI Tone"}'
```

## ファイル構成

```
remove-ai-tone/
├── .claude-plugin/
│   └── plugin.json
├── output-styles/
│   └── remove-ai-tone.md   # 出力スタイル定義 (Remove AI Tone)
├── CHANGELOG.md
└── README.md
```
