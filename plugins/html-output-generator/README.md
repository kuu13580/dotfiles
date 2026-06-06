# html-output-generator

会話内容や markdown ファイルをシンプルで見やすい HTML に変換するプラグインです。HTML 組み立ては**トークン消費の少ない sonnet サブエージェント (`html-builder`) に委譲**することで Opus の負担を抑えます。

## 使い方

Claude Code で以下のコマンドを実行:

```shell
# 直近の会話内容を HTML 化 (assistant が直前に出力した markdown を変換)
/html-output

# markdown ファイルを HTML 化
/html-output path/to/file.md
```

出力ファイルは現在のワーキングディレクトリに、入力の H1 / 主見出しから自動生成された slug 名 (`<slug>.html`) で保存されます。同名ファイルがある場合は `-2`, `-3` のサフィックスを付けて衝突回避します。

## UI 規約

- シンプルなレイアウト (max-width: 800px、システムフォント)
- 不要な背景色・カラーリングを付けない
- 強調 / 比較が必要な箇所のみ色分け
  - `<mark>` / `.highlight`: 黄色ハイライト
  - `.diff-old`: 赤文字 (Before / 旧)
  - `.diff-new`: 緑文字 (After / 新)
- フロー / アーキテクチャ / シーケンス図は mermaid 記法で挿入 (元情報に該当する記述がある場合のみ)

## 設計上の特徴

- **2 層構成 (skill + agent)**: skill (Opus 実行) は入力ソース決定・出力パス決定・委譲のみ。HTML 本体生成は agent (Sonnet 実行) が担当
- **情報追加の禁止**: 入力にない情報の補完・要約・例示・装飾の追加を skill / agent の両方で明示的に禁止
- **mermaid は CDN 読込**: `cdn.jsdelivr.net/npm/mermaid@10` から読み込み。生成 HTML をブラウザで開くだけで図が描画される

## ディレクトリ構成

```
html-output-generator/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── html-output/
│       ├── SKILL.md           # スキル本体 (Opus 実行・委譲ロジック)
│       └── assets/
│           └── template.html  # 出力 HTML のスケルトン (CSS + mermaid CDN)
└── agents/
    └── html-builder.md        # sonnet モデルで動作する変換専門エージェント
```

## 前提条件

- Claude Code (skill + agent 対応バージョン)
- ブラウザでオンライン環境 (生成 HTML 内の mermaid CDN 読込に必要)
