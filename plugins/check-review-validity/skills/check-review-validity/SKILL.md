---
name: check-review-validity
description: "旧 check-review-validity プラグインの入口。check-review-validity は review-kit プラグインに移ったため、review-kit の check-review-validity に引き継ぐか、review-kit の導入を案内する。"
argument-hint: "[<PR番号> | <PR URL>]"
disable-model-invocation: true
---

# check-review-validity (review-kit へ移設済み)

check-review-validity は review-kit プラグインに移った。このスキルは review-kit へ案内するだけで、レビューはしない。

1. Skill ツールで `review-kit:check-review-validity` を呼べるか確かめる
2. 呼べる → 次の1行を伝えてから、`$ARGUMENTS` をそのまま渡して `review-kit:check-review-validity` を呼び、以降はそちらに従う
   > check-review-validity は review-kit に移りました。今後は `/review-kit:check-review-validity` で呼べます。旧プラグインは `/plugin uninstall check-review-validity@kuu13580-marketplace` で外せます
3. 呼べない → 次を伝えて終了する
   > check-review-validity は review-kit プラグインに移りました。次の順に実行してください。
   > 1. `/plugin marketplace update kuu13580-marketplace` (一覧に review-kit を載せる)
   > 2. `/plugin install review-kit@kuu13580-marketplace`
   > 3. `/review-kit:check-review-validity <今回の引数>` で動くことを確かめる
   > 4. `/plugin uninstall check-review-validity@kuu13580-marketplace` で旧プラグインを外す
