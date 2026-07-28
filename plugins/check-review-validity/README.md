# check-review-validity

GitHub PR に自分が書いた **未 submit のドラフトレビュー** (GitHub の Pending review) を、submit する前に検証する read-only スキル。各指摘を ✅ 妥当 / ✏️ 要修正 / ❌ 取り下げ推奨 / ❓ 要確認 に分類し、理由付きでレポートする。

レビューで最もコストが高いのは、事実誤認の指摘に実装者が反論のための時間を使うこと。このスキルはそれを相手に届く前に見つけることを目的にしている。

## 特徴

- **read-only**: GitHub への書き込みは一切しない。ドラフトの編集・削除・submit もしない。反映は GitHub UI でユーザーが判断する。
- **事実正しさ優先**: `diff_hunk` だけで判断せず、ローカルの実ファイルを読んで「既に対応済み」「誤読」「PR のスコープ外」を検出する。
- **重複検出**: submit 済みレビューや他レビュアーのスレッドと同じ指摘を出していないか確認する。
- **外部事実の裏取り**: 「この API は非推奨」等、コードを読むだけでは決まらない技術的主張のみ WebSearch で確認し、ソース URL を併記する。
- **文面案の提示**: ✏️ 要修正 にはそのまま貼れる修正後の文面を添える。

## 使い方

```bash
# カレントブランチに対応する PR のドラフトを検証
/check-review-validity

# PR 番号指定 (カレントリポジトリ)
/check-review-validity 123

# PR URL 指定 (別リポジトリも可)
/check-review-validity https://github.com/owner/repo/pull/123
```

レビュー対象の PR を `gh pr checkout <N>` してから引数なしで実行するのが最も精度が高い。

## 前提条件

- `gh` CLI がインストール済みかつ認証済み (`gh auth login`)
- `jq` がインストール済み
- 検証対象のドラフトレビューが GitHub 上に存在すること (「Start a review」でコメントを付け、まだ submit していない状態)

## 判定軸

| 軸 | 見るもの |
| --- | --- |
| 事実正しさ | ローカルの実ファイル (or `gh pr diff`)。既に手当て済み / 誤読 / PR の変更範囲外への指摘 / `outdated` |
| 規約整合 | `CLAUDE.md`、`.claude/rules/`、lint・tsconfig 設定、周辺コードの既存パターン |
| PR 文脈 | PR description、submit 済みレビュー、他レビュアーのスレッド (重複・蒸し返しの検出) |
| 伝わり方 | 根拠の記載、nit と blocking の区別、1 コメントへの複数指摘の混在、過剰要求 |
| 外部事実 | 上記で真偽が決まらない技術的主張のみ WebSearch / WebFetch |

## 出力例

```
## PR #6290 SearchのSignal移行 — ドラフト 4 件
https://github.com/owner/repo/pull/6290

| # | 判定 | 場所 | 一言 |
|---|------|------|------|
| 1 | ❌ 取り下げ | search.component.ts:42 | 18行目で既に移行済み、事実誤認 |
| 2 | ✏️ 要修正 | search.store.ts:88 | 指摘は妥当だが根拠が未記載 |
| 3 | ✅ 妥当 | search.service.ts:15 | そのまま submit 可 |
| 4 | ❓ 要確認 | search.store.ts:200 | 意図が読めず実装者に確認すべき |

### [1] ❌ 取り下げ推奨 — search.component.ts:42
> takeUntil でなく takeUntilDestroyed に統一すべき

同ファイル 18 行目で既に takeUntilDestroyed に移行済み。
42 行の takeUntil は外部購読に対するもので置換対象外。

### [2] ✏️ 要修正 — search.store.ts:88
> ここは computed にした方がいい

指摘は妥当 (signal から派生する値)。ただし根拠がなく実装者が判断できない。

**文面案**: 「88 行の value は queryParams からの派生値なので
computed() にすると再計算漏れを防げます」

---
補足 (見落とし候補): store.ts:120 の effect が cleanup 未登録
サマリ: ✅ 1 / ✏️ 1 / ❌ 1 / ❓ 1
```

## `pr-bot-watcher` / `/code-review` との違い

| 観点 | check-review-validity | pr-bot-watcher | /code-review |
| --- | --- | --- | --- |
| 対象 | **自分の未 submit ドラフト** | 他者 (bot) の submit 済みコメント | PR の変更差分そのもの |
| 立場 | レビュアー (送る側) | 実装者 (受ける側) | レビュアー (新規レビュー) |
| 網羅性レビュー | しない (末尾に補足 1-3 件のみ) | しない | する |
| 書き込み | なし | 修正 commit / push / 返信 | なし |

submit 前のセルフチェックが `check-review-validity`、届いた指摘の処理が `pr-bot-watcher`、ゼロからレビューを書くのが `/code-review`。

## ファイル構成

```
check-review-validity/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── check-review-validity/
│       ├── SKILL.md
│       └── scripts/
│           └── fetch-pending-review.sh   # ドラフトレビュー + 判定材料の取得
├── CHANGELOG.md
└── README.md
```

## 制約

- 未 submit のドラフトは **本人にしか見えない**。他人のドラフトを検証することは API 上できない。
- GitHub 仕様上、1 ユーザーが 1 PR に持てる pending review は 1 つだけ。
- 別リポジトリの PR を URL で指定した場合、`CLAUDE.md` や lint 設定が読めないため規約軸の判定は保留される。
