---
name: pr-review
description: "旧 pr-review プラグインの入口。pr-review は review-kit プラグインに移ったため、review-kit の pr-review に引き継ぐか、review-kit の導入を案内する。"
argument-hint: "[<PR番号> | <PR URL>] [--review | --verify] [--no-explain] [medium | high | xhigh | max] [+security | +behavior | +ui | +migration | +test]"
disable-model-invocation: true
---

# pr-review (review-kit へ移設済み)

pr-review は review-kit プラグインに移った。このスキルは review-kit へ案内するだけで、レビューはしない。

1. Skill ツールで `review-kit:pr-review` を呼べるか確かめる
2. 呼べる → 次の1行を伝えてから、`$ARGUMENTS` をそのまま渡して `review-kit:pr-review` を呼び、以降はそちらに従う
   > pr-review は review-kit に移りました。今後は `/review-kit:pr-review` で呼べます。旧プラグインは `/plugin uninstall pr-review@kuu13580-marketplace` で外せます
3. 呼べない → 次を伝えて終了する
   > pr-review は review-kit プラグインに移りました。次の順に実行してください。
   > 1. `/plugin marketplace update kuu13580-marketplace` (一覧に review-kit を載せる)
   > 2. `/plugin install review-kit@kuu13580-marketplace`
   > 3. `/review-kit:pr-review <今回の引数>` で動くことを確かめる
   > 4. `/plugin uninstall pr-review@kuu13580-marketplace` で旧プラグインを外す
