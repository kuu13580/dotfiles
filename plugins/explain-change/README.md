# explain-change

PR / commit / ブランチ / 現 worktree の変更を調査し、**その領域を知らない読者がゼロから読み解ける長文解説** を Artifact として 1 本 publish する read-only スキル。

diff だけ眺めても頭に入らない理由は差分の情報量ではなく、**差分が乗っている既存システムを知らないこと** にある。このスキルは diff の要約ではなく、その diff を理解するのに必要な既存システムを先に立ち上げてから変更を説明する。

## 使い方

```bash
/explain-change                                       # 未コミット変更 (なければカレントブランチの PR)
/explain-change 123                                   # PR #123
/explain-change https://github.com/o/r/pull/123       # 別リポジトリの PR も可
/explain-change abc1234                               # commit 単体
/explain-change 80d21c4..d0027ad                      # 範囲
/explain-change feat/foo                              # ブランチ (デフォルトブランチとの merge-base から)
```

対象の判別は `scripts/resolve-target.sh` が行う。判別できない引数は勝手に別の対象へ倒さず、ユーザーに確認する。

あわせて `local_code` を `exact` / `contains` / `absent` の 3 値で返し、調査方法を決める。マージ済み PR は手元のファイルが読めるので `contains` に落ち、diff だけに縮退しない (squash / rebase merge は head が HEAD の祖先にならないため、マージコミット経由で判定する)。

## 出力

5 章構成の HTML を Artifact として publish し、URL を返す。

| 章 | 内容 |
| --- | --- |
| この変更は何か | 3 行サマリ |
| 背景 | 初見向けの全体像 → 変更箇所周辺の具体契約 |
| 直感 | トイデータ + before/after で核心を渡す |
| コードの歩き方 | 実行順にグルーピング、`file:line` 付き |
| 押さえどころ | 影響範囲 / 落とし穴 / 未解決の痛み |

## 設計上の判断

- **背景は深く、範囲は狭く。** 背景章に紙幅を割くが、書くのは「これを知らないと diff が読めない」ものだけ。モジュール全体の解説には膨らませない。
- **事実と推測を視覚的に分ける。** 本文はコードと一次情報から確かめられたことだけを断定で書き、動機の推測は根拠付きの専用コールアウトに隔離する。自信ありげな誤った推測は、知らない読者に嘘を植え付けるため。
- **図は多めに、型は 3-4 種に固定。** 各章に最低 1 枚。インライン SVG (機構そのもの) を第一候補に、mermaid (分岐の多いフロー) と HTML+CSS (before/after 対比・整列) を使い分ける。矢印にはラベル、図には具体値。ASCII 図は使わない。
- **Artifact 出力。** 成果物は Artifact の URL で渡し、リポジトリにはファイルを残さない (html-output-generator を deprecated にした判断と揃える)。
- **調査方法は固定しない。** サブエージェントへの委譲は状況判断に任せ、「コンテキストを食い潰して薄い解説にしない」という制約だけ課す。

## 前提条件

- `git`、`jq`
- PR を対象にする場合のみ `gh` CLI (認証済み)

## `/code-review` / `check-review-validity` との違い

| 観点 | explain-change | /code-review | check-review-validity |
| --- | --- | --- | --- |
| 目的 | **理解する** | 欠陥を見つける | 自分の指摘を検証する |
| 立場 | 読み手 | レビュアー | レビュアー (送る前) |
| 出力 | Artifact の長文解説 | 指摘リスト | 判定レポート |

欠陥探しはこのスキルの仕事ではない。気づいた問題は「押さえどころ」に落とし穴として触れる程度に留める。

## ファイル構成

```
explain-change/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── explain-change/
│       ├── SKILL.md
│       └── scripts/
│           └── resolve-target.sh   # 対象の判別と調査メタデータの取得
├── CHANGELOG.md
└── README.md
```

## 制約

- read-only。`git checkout` / commit / push / GitHub への書き込みはしない。
- 手元にコードが無い場合 (`local_code: absent`) は checkout させず、diff ベースの解説である旨を明記して続行する。
- 対象が大きすぎるときは中心的な変更に絞り、割愛した範囲を冒頭に明記する。
