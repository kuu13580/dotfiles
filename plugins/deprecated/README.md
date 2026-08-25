# deprecated

marketplace から除外したプラグインの保管場所。`.claude-plugin/marketplace.json` に未登録なので配布・ロードはされない (参照・復活用に実体だけ残す)。

| 廃止日 | プラグイン | 理由 |
| --- | --- | --- |
| 2026-08-26 | html-output-generator (v1.0.0) | Claude Code 標準の Artifact 機能で代替可能になったため |

復活させる場合は `git mv plugins/deprecated/<name> plugins/<name>` した後、`.claude-plugin/marketplace.json` と `plugins/README.md` に再登録する。
