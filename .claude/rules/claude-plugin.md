---
paths:
  - "plugins/**"
  - ".claude-plugin/marketplace.json"
---

# プラグイン追加・編集時のルール

新しいプラグインを `plugins/` に追加するときは:

1. `.claude-plugin/marketplace.json` の `plugins` 配列に登録する (`name` / `source` / `description`)。
2. `plugins/README.md` の一覧に概要を追記する (1行サマリ + 主要コマンド/用途 + 個別 README へのリンク)。
3. プラグイン本体のディレクトリに個別 README を置く。

ルート `README.md` は**編集不要**。プラグインの詳細は `plugins/README.md` に集約し、ルートからはそこへリンクするだけにする。
