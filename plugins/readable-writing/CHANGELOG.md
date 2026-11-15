# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-11-16

### Added

- 人が読む文章の構成と情報の並べ方の原則集 skill `readable-writing` を追加。どの文章でも読む `principles.md`、目的別の5つの reference(判断 / 把握 / 実行 / 後で引く / 理解)、ターン制の対話用の `conversation.md` に分けて収録
- 文脈判定(目的・読み手・読まれ方・媒体の性質)と振り分け表で、必要な reference だけを読む
- 受付箱 `~/.claude/readable-writing/inbox.md`: 作業中の直しを聞かずに候補として溜め、取り込むときにまとめて採否を決める
