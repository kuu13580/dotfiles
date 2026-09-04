# prepare-context

セッションや compact を跨いでも設計判断が失われないようにするための、引き継ぎ記録の運用をプラグイン化したもの。

確認した事実と決定を `~/.claude/contexts/<repo>/<key>/CONTEXT.md` に残し、`SessionStart` フックが (compact 後も含めて) 自動的に読み戻す。

## 解決したい問題

| 問題 | 現状 |
| --- | --- |
| 1セッションで進めるとノイズが溜まる | 調査ログ・撤回された指摘・試行錯誤が同じ文脈に積み上がり、compact で結論が薄まる |
| セッションや compact を跨ぐと決定が失われる | 設計時の判断根拠が後続フェーズに届かず、同じ議論を繰り返す |
| 同一タスクの別セッションへ指摘が伝わらない | 同じ誤りを繰り返し、原因が追いにくくなる (記録に書けば全セッションへ注入される) |

## 使い方

```bash
/prepare-context 調査   # 確認した事実を根拠付きで書き出す
/prepare-context 設計   # 決定 (論点・決定・理由) と前提・保留を書き出す
/prepare-context 実装   # 決定の変更履歴と新事実を追記する
/prepare-context pr     # コードから読み取れない設計思想を PR 本文の素材として出す
```

読み込みに専用の入口は無い。通常は `SessionStart` が担い、途中の読み直しはスキルが拾う。

## 記録の構成

`~/.claude/contexts/<repo>/<key>/` に2ファイル。

| ファイル | 役割 | 上限 |
| --- | --- | --- |
| `CONTEXT.md` | 現役の事実・決定・保留。`SessionStart` で自動注入される | **400行 / 24KB** |
| `CONTEXT.archive.md` | 撤回された決定と理由、詳細な根拠。注入しない | なし |

上限を設けているのは、膨張の本当のコストがトークンではなく**信号の希釈**だから。運用実績のある記録は 8.6KB / 15.3KB まで膨らみ、3章構成の規約からも逸脱していた。「事実を捨てない」と「注入を膨らませない」を両立させるため、削らず archive へ移す。

**上限は強制上限ではなく警報**として置いてある。要約による圧縮は禁止で、選択肢は「archive へ移す」か「そのまま残す」の2つだけ。上限をきつくすると、モデルが記録を要約して根拠を落とし、このプラグインが防ごうとしている compact と同じ失敗を再生産する。判断がつかないものは残す側に倒す (archive は注入されないため、誤って移すと失われたのと同じになる)。

24KB という値は実測から置いた: 中規模タスクの記録が 7.7KB、実装が4フェーズ進んだタスクが 8.6KB、設計を完全に詰めた状態が 15.3KB。大きめのタスクの正当な記録が 15〜20KB に着地するため、それより上に余裕を取っている。

### キーの解決

`scripts/resolve-key.sh` が `<repo>/<key>` を1行で返す。

1. `git config --worktree prepare-context.key <slug>` が設定されていれば `<repo>/<slug>`
2. なければ非 default branch のとき `<repo>/<branch>` (`/` と空白は `-` に畳む)
3. default branch (`main` / `master` / `develop` / `origin/HEAD` の指す先) / detached HEAD / 非 git → `exit 1`

明示キーをブランチ名より先に見るのは、**タスク途中でブランチを切っても記録が孤立しない**ようにするため。`main` で調査してからブランチを切る流れが普通で、そこでキーが変わると直前まで書いた記録を見失う。`git config --worktree` は worktree スコープなので、1 worktree = 1タスクの粒度と一致する。

default branch で自動解決を拒むのは、同一リポジトリの別タスクが同じキーを踏むと**他タスクの決定表に追記して過去の決定を汚染する**ため。記録が無い状態より悪い失敗なので、黙って解決しない。

## SessionStart フックの挙動

| 状態 | 出力 |
| --- | --- |
| キー未解決 | 無音 (exit 0)。`main` での雑用・レビューセッションにノイズを出さない |
| キー解決済み・記録なし | 書き出しを促す1行 |
| キー解決済み・記録あり | `CONTEXT.md` 全文 |
| 上記に加え上限超過 | archive への追い出しを促す1行 |
| 上記に加え `source=compact` | 「圧縮サマリと突き合わせ、記録に無い決定を追記せよ」の1行 |

注入は **stdout** を使う。プラグイン同梱の `SessionStart` では `hookSpecificOutput.additionalContext` が Claude に渡らない既知の不具合があり、修正予定もない ([#16538](https://github.com/anthropics/claude-code/issues/16538) Closed as not planned)。

**stdout 経由の注入はプラグイン同梱の `SessionStart` でも機能する** (v0.1.0 時点で実測)。推測不能な canary トークンを `CONTEXT.md` に仕込み、ツール使用を禁じて `claude -p` に出力させて完全一致を確認。キーが解決しないディレクトリでは注入されない negative control も通した。[#16538](https://github.com/anthropics/claude-code/issues/16538) が壊れていると報告しているのは `additionalContext` であって stdout ではない。

検証は `~/.claude/skills/<name>/` へのシンボリックリンクで行える (`<name>@skills-dir` として次セッションで自動ロードされる)。marketplace を汚さず、リンク削除だけで撤収できる。

## 意図的にやらないこと

| やらないこと | 理由 |
| --- | --- |
| 記録の自動生成 | 信号とノイズの仕分けに LLM 判断が必要。明示コマンドで行う |
| 指摘・事実の一般化 (`CLAUDE.md` / `.claude/rules/` への昇格) | **スコープ外。**知識ベースの蓄積であって、compact とセッションを跨いで決定を保つという目的とは別物。一般化できる事実が出てきたら、その場で `CLAUDE.md` に書けば済む |
| `PreCompact` フック | コマンドフックは記録を書けず、出せるのは指示文のみ。それが読まれる時点で素材は圧縮済み。記録の再注入は `SessionStart` (source=`compact`) が担保する |
| `Stop` フック | 毎回の停止で走るためコストが読めない。運用してから必要性を判断する |
| `commands/` | スキルが引数を受け取れ (`/prepare-context 設計`) 自然言語でも発動するため、規約と入口を兼ねられる。入口を二重化しない |
| リポジトリ内への記録の配置 | `.gitignore` と PR の diff を汚さない。個人の作業スタイルであってリポジトリの規約ではない |
| 記録のリポジトリへのコミット | 同上 |

## 構成

```
prepare-context/
  .claude-plugin/plugin.json
  hooks/hooks.json                                SessionStart のみ
  scripts/resolve-key.sh                          キー解決 (フックとスキルの両方から呼ぶ)
  scripts/load-record.sh                          SessionStart 本体
  skills/prepare-context/SKILL.md                 規約と入口
  skills/prepare-context/references/template.md   2ファイルの雛形
```
