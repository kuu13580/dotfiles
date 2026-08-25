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

# プラグイン廃止時のルール

プラグインを廃止するときは**削除せず** `plugins/deprecated/<name>/` へ退避する:

1. `git mv plugins/<name> plugins/deprecated/<name>` で実体を移動する (中身は改変しない)。
2. `.claude-plugin/marketplace.json` の `plugins` 配列から該当エントリを削除する。
3. `plugins/README.md` の一覧から該当セクションを削除する。
4. `plugins/deprecated/README.md` の表に「廃止日 / プラグイン名 / 理由」を1行追記する。
5. 退避した個別 README の先頭に廃止バナーを1行入れる。

`plugins/deprecated/` 配下は marketplace 未登録のため配布・ロードされない。復活は逆手順。
