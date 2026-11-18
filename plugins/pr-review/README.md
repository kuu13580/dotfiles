# pr-review

pr-review は [review-kit](../review-kit/README.md) プラグインに移した。このプラグインは、今までどおり `/pr-review` で呼ばれたときに review-kit へ案内するためだけに残している。

## 呼んだときの動き

| review-kit | 動き |
| --- | --- |
| 入っている | 移設と今後のコマンド (`/review-kit:pr-review`) を1行伝え、引数をそのまま渡して `review-kit:pr-review` に引き継ぐ |
| 入っていない | review-kit の入れ方と、このプラグインの外し方を伝えて終わる |

## 移行

```bash
/plugin marketplace update kuu13580-marketplace
/plugin install review-kit@kuu13580-marketplace
/review-kit:pr-review                                  # 動くことを確かめる
/plugin uninstall pr-review@kuu13580-marketplace
```

pr-review の機能と移設時の変更点は [review-kit の README](../review-kit/README.md) と [CHANGELOG](../review-kit/CHANGELOG.md) を参照。
