# review-kit

Claude が行うすべてのレビューで同じ原則を使うためのプラグイン。原則を `references/principles.md` の1か所に置き、4つのスキルがそこから読む。

## スキル一覧

| スキル | 使う場面 | やること | GitHub への書き込み |
| --- | --- | --- | --- |
| self-review | 実装の区切り (一時 commit の前、PR を出す前) | 自分の差分を洗い出し → 検証 → 議論 → その場で直す | なし |
| review-response | 自分の PR に指摘 (人・bot) が来たとき | 指摘を検証 → 議論 → 直す → 全件の返信案 → 承認後に push・返信・再レビュー依頼 | 返信・再レビュー依頼 (人への返信は承認後) |
| pr-review | 他人の PR のレビュー、修正確認 | 洗い出し → 検証 → 議論で決めた重さを文面に出して pending 投稿 → 修正確認・Resolve・Approve | pending 投稿は確認なし。Approve・返信・Resolve は承認後。submit はしない |
| check-review-validity | 自分の未 submit の下書きレビューがあるとき | 下書きの各指摘を検証して ✅ / ✏️ / ❌ / ❓ に分類 | なし |

4つとも自然文で呼べる (Claude が自分で起動できる)。各スキルは冒頭で `scripts/detect-state.sh` を実行してローカルと GitHub の状態を見て、別のスキルが合えば切り替えを提案する。判定表は [references/routing.md](references/routing.md)。

## 共通の原則

流れは **洗い出す → 検証する → 3軸で議論する → 決める**。詳細は [references/principles.md](references/principles.md)。

- **観点**: 基本の3軸は固定し、変更の中身で追加観点を足す
  - 3軸: 正しさ (ビルトイン `/code-review` に任せる) / 仕様・使う人 / 保守・構造
  - 追加観点: セキュリティ・既存動作の変更・UI・データ移行・テスト・失敗・再実行・破壊的な挙動 (仕様どおりでも、データの上書き・外部への送信などを確認に回す)。差分のファイル種別やパスで自動で足し、引数 `+security` などでも足せる
- **洗い出し**: 全候補に「具体的な入力・状態 → 誤った結果」を付け、半信半疑の候補も落とさない
- **確度**: 高 (テストかコードで確定) / 中 (仕組みは実在、きっかけが不確か) / 取り下げ (否定する行を引用できたものだけ)
- **3軸の議論**: 各軸が 直す / 直さない / 保留 を出す。一致で決定、2対1 は多数決で少数意見を報告、割れたときやデータの破損に関わるときはユーザーに委ねる
- **規約違反**: 規約の原文と違反行を引用できたら議論にかけずに直す・投稿する。lint が拾うものは指摘しない
- **漏れ探し**: level `max` のときだけ、検証済みリストに無いものを新しい担当が探す

## トークン量の計測

各スキルは最後の報告に、その回で使ったトークン量を1行で付け、`~/.claude/review-kit/usage.tsv` に追記する。メインとサブエージェントの分を合わせ、新規に処理した量 (入力 + キャッシュ書き込み + 出力) とキャッシュ読み込みを分けて出す。あとから見るときは次を実行する:

```bash
python3 plugins/review-kit/scripts/usage-report.py --all   # このセッションの回ごと
column -t -s $'\t' ~/.claude/review-kit/usage.tsv         # これまでの記録
```

1回の範囲は、スキルを呼んだ時点から次に review-kit のスキルを呼ぶまで。review-response の中で呼ぶ self-review は別の回として出る。

## 使い方

```bash
/self-review                       # 未コミットの変更 (無ければブランチ全体) を見直して直す
/self-review high +security        # level と追加観点を指定
/review-response                   # カレントブランチの PR に来た指摘に対応
/pr-review                         # 自分宛のレビュー依頼一覧から選ぶ
/pr-review 123 max                 # level max (漏れ探しあり) でレビュー
/check-review-validity 123         # PR #123 の下書きレビューを検証
```

pr-review の引数 (`--review` / `--verify` / `--no-explain`) とフェーズの詳細は [skills/pr-review/SKILL.md](skills/pr-review/SKILL.md)。

## 前提条件

- `gh` CLI がインストール済みかつ認証済み (`gh auth login`)
- `jq` / `python3` / `git` がインストール済み
- 任意: `explain-change` (pr-review が変更の解説に使う)、`ui-principles` (UI の追加観点で使う)、`readable-writing` (報告に使う)。無ければその部分を省いて進む

## ファイル構成

```
review-kit/
├── .claude-plugin/plugin.json
├── references/
│   ├── principles.md            # 共通の原則 (観点・洗い出し・確度・直す判断・3軸の議論)
│   └── routing.md               # 状態から合うスキルを選ぶ表
├── scripts/
│   ├── detect-state.sh          # ローカルと GitHub の状態から合うスキルを判定
│   ├── usage-report.py          # スキル実行で使ったトークン量をセッションの記録から集計
│   └── reply-thread.sh          # レビュースレッドに返信 (pr-review / review-response)
├── skills/
│   ├── self-review/SKILL.md
│   ├── review-response/
│   │   ├── SKILL.md
│   │   └── scripts/fetch-pr-feedback.sh   # 自分の PR に来た未解決の指摘とレビュアーの状態
│   ├── pr-review/               # SKILL.md / references (フェーズA・B) / scripts
│   └── check-review-validity/   # SKILL.md / scripts
├── CHANGELOG.md
└── README.md
```

## 旧プラグインからの移行

`pr-review` (v0.7.0) と `check-review-validity` (v1.0.1) はこのプラグインに移した。移した時点での変更点は [CHANGELOG.md](CHANGELOG.md)。

旧プラグインは、review-kit へ案内するだけのプラグインとして marketplace に残している。今までどおり `/pr-review` などで呼ぶと、review-kit が入っていればそちらに引き継ぎ、入っていなければ入れ方を案内する。移行は `/plugin install review-kit@kuu13580-marketplace` のあと、`/plugin uninstall pr-review@kuu13580-marketplace` などで旧プラグインを外す。
