# antigravity

Claude Code 用のプラグイン・ルール資産 (`plugins/`, `CLAUDE.md`) を無改造のまま Antigravity (Gemini) に適応させるための設定・アダプタ群。

## 構成

| ファイル | 役割 | リンク先 |
| --- | --- | --- |
| `AGENTS.md` | グローバルルール (`CLAUDE.md` 継承 + ツール/パス読み替え規約) | `~/.gemini/config/AGENTS.md` |
| `skills.json` | `plugins/*/skills` を直接マウントする設定 | `~/.gemini/config/skills.json` |
| `hooks.json` | Antigravity ライフサイクルフック定義 | `~/.gemini/config/hooks.json` |
| `scripts/prepare-context-hook.sh` | `PreInvocation` 用コンテキスト注入アダプタ | — |
| `scripts/guard-worktree.sh` | `PreToolUse` 用 git worktree 直接操作ガード | — |

## セットアップ

```bash
./setup-antigravity.sh
```

## 設計方針

- **Single Source of Truth**: スキル本体やルールは複製せず、`skills.json` と symlink で dotfiles 側を直接参照。
- **Claude 純正の維持**: `plugins/` や `CLAUDE.md` は変更せず、Antigravity 側の指示書 (`AGENTS.md`) でツールの差異を吸収。
