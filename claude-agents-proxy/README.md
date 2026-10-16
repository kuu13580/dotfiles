# claude-agents-proxy

Windows Terminal で `claude agents` (Agent View) を使うと、セッション表示中にウィンドウをスナップ (全画面・半分) してから ⏪ で一覧に戻ったときに、描画が崩れたまま戻らなくなる。これを避けるための PTY プロキシ。

## 仕組み

`claude agents` を PTY 越しに起動し、出力から alt screen 切替 (`ESC[?1049h` など) を取り除く。代わりに画面を消去し、端末幅を 1 列縮めて戻す SIGWINCH を送って全体を描き直させる。

- Agent View は画面遷移のたびに `ESC[?1049h` を送り直す。スナップ時のリサイズは途中のサイズを挟むため、Windows Terminal / ConPTY 側の alt バッファがずれると見ている (推測)
- 崩れた後に外から SIGWINCH や画面消去を送っても直らず、手でリサイズすると直る。原因は Claude 側ではなく端末側のバッファにあると判断した

## 使い方

`.zshrc` から `claude-agents.zsh` が source され、`WT_SESSION` がある (Windows Terminal) ときの `claude agents` だけが `proxy.py` 経由になる。それ以外のコマンドや端末では素の `claude` を呼ぶ。

```sh
proxy.py --log            # private mode の切替を ~/.cache/claude-agents-proxy.log に記録
proxy.py --keep-alt       # alt screen 切替を止めない (記録だけ取りたい時)
```

## 副作用

- alt screen を使わないため、終了後もシェルのスクロールバックに Agent View の画面が残る
- 素の `claude agents` で起動したい場合は `command claude agents`
