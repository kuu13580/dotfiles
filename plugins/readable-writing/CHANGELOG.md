# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] - 2026-11-18

### Changed

- `principles.md`: 「箇条書きの1段目には名前や結論だけを置く」に、名前と説明を「:」でつないで1段目に詰めた形(「案1 割り切り: 実装は最小。〜」)は違反だと明記
- `SKILL.md`: 手順に「書き終えて出力したあと、原則どおりか見直す」を追加

## [1.0.1] - 2026-11-17

### Changed

- `conversation.md`: 読み手が外部の資料を開けないチャットでは、判断に要る材料を削らず同じ返答の中で上下に分ける原則を追加(上に決めてほしいこと・重要な情報を目立たせ、下に「読まなくても選べる」裏づけ)。「出典・経緯は聞かれたら出す」は、判断に使わない部分に限定

## [1.0.0] - 2026-11-16

### Added

- 人が読む文章の構成と情報の並べ方の原則集 skill `readable-writing` を追加。どの文章でも読む `principles.md`、目的別の5つの reference(判断 / 把握 / 実行 / 後で引く / 理解)、ターン制の対話用の `conversation.md` に分けて収録
- 文脈判定(目的・読み手・読まれ方・媒体の性質)と振り分け表で、必要な reference だけを読む
- 受付箱 `~/.claude/readable-writing/inbox.md`: 作業中の直しを聞かずに候補として溜め、取り込むときにまとめて採否を決める
