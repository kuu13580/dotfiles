# md-view

Claude の返答に含まれる ```` ```mermaid ```` ブロックを図として表示し、`/md` で Markdown ファイルを pane に表示する mod。図にできる環境では、mermaid を使ってよいことをシステムプロンプトで Claude に伝える。

## 機能

| 対象 | 動作 |
| --- | --- |
| 返答中の mermaid | 端末は `leaf --inline plain:<幅>` の ASCII 図を ```` ```text ```` フェンスに差し替えて表示する。Desktop / VS Code は `mmdc` の SVG を表示し、mmdc がなければ leaf の ASCII 図を表示する。保存される本文は元のまま (ctrl+o で原文)。```` ````markdown ```` など他のコードフェンスの中に書かれた mermaid は図にしない |
| `/md [path]` | Markdown ファイルを pane に表示する。引数なしは直前に表示したファイル。本文は Claude の返答と同じ Markdown 描画で、mermaid だけ上と同じ方法で図にする |
| pane のボタン | `l`: leaf で全文を描画する表示との切替 / `f`: Claude が Write・Edit した .md への追従の ON・OFF (pane を開いている間だけ) / `r`: 再読込 |
| ファイルの更新 | pane を開いている間、1.5 秒ごとに更新日時と pane 幅を確認し、変わっていれば描き直す |
| システムプロンプト | 図にできる surface (端末 + leaf、Desktop / VS Code + mmdc か leaf) があるときだけ、「説明が図で速く伝わるときは mermaid を使ってよい。短い返答や本文の繰り返しになる図は不要」という一節を足す |

leaf / mmdc がなければ mermaid はソースのまま表示し、入れ方を toast で知らせる (surface ごとに一度だけ)。mod が自動で導入することはない。コマンドの有無は 30 秒おきに確認し直すため、後から入れても reload は不要。システムプロンプトは会話の最初に決まるため、一節が足されるのは入れた後の新しい会話から。

**Team / Enterprise の組織や管理設定のある PC ではシステムプロンプトの一節は効かない**: 組み込みの `cc-plugin-sec-default` が、ユーザーが入れたプラグインの `prompt.compose` などプロンプトを変えるイベントを飛ばすため (起動時に「md-view: its prompt.compose hook was skipped」と出る)。図の描画は動く。mermaid を使わせたい場合は CLAUDE.md に書く。

**モバイルは対象外**: モバイルアプリは描画先として扱わず、mermaid はソースのまま表示する (保存本文は書き換えない方針のため)。

## 依存

どちらも任意。入れたものの範囲で図になる。どちらも apt にはなく、snap にあるものは作者以外の配布のため使わない。

**leaf** (端末の ASCII 図): Rust 製の単体バイナリ。次のどれかで入れる。他の方法は [leaf の README](https://github.com/RivoLink/leaf#install)。

```sh
curl -fsSL https://raw.githubusercontent.com/RivoLink/leaf/main/scripts/install.sh | sh   # 公式スクリプト (Node 不要)
brew install leaf-markdown-viewer
npm install -g @rivolink/leaf
```

**mermaid-cli** (Desktop / VS Code の SVG、コマンド名 `mmdc`、12.0.0 以降): 公式の配布は npm と Docker のみ。md-view は PATH 上の `mmdc` を呼ぶため npm で入れる。11 系は `--no-font-embed` がなく SVG を作れないため、図は leaf の ASCII 図かソースになる。

```sh
npm install -g @mermaid-js/mermaid-cli
```

mermaid-cli は Puppeteer 経由で Chromium をダウンロードして使うため、導入サイズが大きく、1 図あたりの描画にも数秒かかる。描画結果はプロセス内にキャッシュする。

mmdc は `htmlLabels: false` と `--no-font-embed` で呼ぶ。既定ではフォント埋め込みで SVG が 200KB 程度になり、`Svg` 要素の上限 (131,072 文字) を超えるため。HTML ラベル (foreignObject) も同じ理由で使わない。上限を超えた図は leaf の ASCII 図かソースで表示する。

## 公式の mermaid 対応との関係

- Claude Code 本体には端末向けの組み込み mod `cc-plugin-mermaid` が同梱されている (フローチャートとシーケンス図を罫線の図にする)。ただし機能フラグ `tengu_mermaid_mod` で止められていて、2.1.322 時点ではユーザー側から有効にできない
- 有効になった場合も、ユーザーが入れたプラグインが組み込みより先に動くため、md-view が描いた図は二重に描かれない。md-view が描けなかった図だけを公式が描く
- Desktop の Claude Code タブは mermaid を図にしない ([anthropics/claude-code#52517](https://github.com/anthropics/claude-code/issues/52517))。Desktop の SVG と `/md` の pane は md-view だけの機能

## ファイル構成

```
md-view/
├── .claude-plugin/plugin.json
├── hooks/
│   ├── hooks.json
│   ├── register.tsx        # 返答の mermaid 描画 / /md pane / システムプロンプトの一節
│   └── register.test.tsx   # claude plugin test plugins/md-view
├── types/index.d.ts        # $.state の型 (md-view.view)
├── CHANGELOG.md
└── README.md
```
