# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-11-20

### Changed

- pr-review: explain-change が入っていないときは、解説ページを作れなかったことと入れ方 (`/plugin install explain-change@<marketplace>`) を報告で案内する。`--no-explain` で省いたときは案内しない

## [0.1.0] - 2026-11-18

### Added

- 共通の原則 `references/principles.md`: 3軸 (正しさ / 仕様・使う人 / 保守・構造) と追加観点 (失敗・再実行、破壊的な挙動を含む)、モックを使って動かして確かめる検証、洗い出しの決まり、確度3段 (高 / 中 / 取り下げ)、直す判断の土台、3軸の議論、`max` での漏れ探し
- 状態からスキルを選ぶ `references/routing.md` と `scripts/detect-state.sh`。各スキルの冒頭で実行し、合うスキルへの切り替えを提案する
- `scripts/usage-report.py`: スキル実行で使ったトークン量をセッションの記録から集計し、各スキルの報告の末尾に1行で出して `~/.claude/review-kit/usage.tsv` に残す
- self-review: 自分の差分を洗い出しから回し、議論の結果に沿ってその場で直す
- review-response: 自分の PR に来た指摘を検証から回し、直す → 全件の返信案 → 承認後に push・返信 → 指摘した人だけに再レビュー依頼。pr-bot-watcher (0.3.0) が bot コメントを検出したあとの引き渡し先にもなる
- pr-review (旧 `pr-review` v0.7.0 から移設)
  - 3系統 (code-review / 規約 / 仕様・設計) を3軸 + 追加観点にそろえた。規約は保守・構造の軸に入れた
  - 保守・構造の整理系 (再利用・簡素化など) を、コストを行で示せるものだけ【改善】として投稿する
  - 確度3段。高は指摘として、中は起きる条件を示した【確認】の問いとして投稿する
  - 取り下げは否定する行を引用できるときだけにした。`max` で漏れ探しをする
  - 3軸の議論の結論を、指摘の重さ (必須 / 任意 / 別 PR でよい) として文面に出す。3軸が割れたものは、どこで直すかを問う【確認】にする
  - 確認が要るものはすべて pending に置き、ターミナルには見なくてよい控えだけを出す。pending はそのまま送れる文面にし、`【確認・要判断/<重要度>】` の目印を外して送る運用をやめた (重要度は `【確認/major】` の形で相手にも伝える)
  - pending は 1 PR あたり 12 件までにし、超えた分は優先順位の低い側から「その他」コメント 1 件にまとめる。規約違反は 3 件以上なら 1 件にまとめる
  - `disable-model-invocation` を外し、自然文で呼べるようにした
  - レビュー後に元のブランチへ戻すかを聞くのをやめ、checkout した事実だけを報告する
  - force push された PR は、ローカルブランチで commit を作った記録 (reflog) が無ければ確認せず `gh pr checkout --force` で合わせる。detached HEAD では開かない
  - 周りの既存コードが同じ書き方でも、引用できる規約違反は落とさず【規約】として投稿し、既存に合わせる判断なら返信で閉じるよう添える
- check-review-validity (旧 `check-review-validity` v1.0.1 から移設)
  - 事実正しさの判定に共通の確度を使う。確度が中なのに断定している下書きは ✏️ にし、問いの形の文面案を出す
  - `disable-model-invocation` を外し、自然文で呼べるようにした

### Changed

- `reply-thread.sh` を pr-review と review-response で共有するため、プラグイン直下の `scripts/` に移した
- 旧 `pr-review` (0.8.0)・`check-review-validity` (2.0.0) は、review-kit へ案内するだけのプラグインとして残した。`/pr-review` などで呼ぶと、review-kit が入っていればそちらに引き継ぐ
