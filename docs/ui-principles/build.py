"""ui-principles の原則を、NG例・OK例付きの静的ページ(index.html)にする。

    python3 docs/ui-principles/build.py

原則は plugin の references を正とし、図解は examples.json に見出しをキーにして置く。
見出しを変えたら examples.json のキーも合わせる(合わないものは実行時に警告する)。
"""
import html
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REFS = HERE.parents[1] / 'plugins' / 'ui-principles' / 'skills' / 'ui-principles' / 'references'

GROUPS = [
    ('どの画面でも読む', ['layout', 'actions', 'feedback', 'form-flow', 'copy']),
    ('部品を作るときだけ読む', ['dialog', 'step-input', 'consent', 'navigation', 'notification', 'motion', 'ai-features', 'map']),
    ('文脈で足す', ['mobile', 'desktop', 'responsive', 'implementation']),
]
RE_FULL = re.compile(r'^### (.+?)〔(必須|推奨)〕\s*$')
RE_SUB = re.compile(r'^#### (.+?)〔(必須|推奨)〕\s*$')
RE_CHECK = re.compile(r'^- (.+?)(〔必須〕)?\s*$')


def parse(path):
    lines = path.read_text(encoding='utf-8').splitlines()
    title = lines[0].lstrip('# ').strip()
    scope = next((l[len('読む場面: '):].split('。')[0] for l in lines if l.startswith('読む場面: ')), '')
    items, cur, in_check, lang = [], None, False, ''
    for l in lines[1:]:
        if l.startswith('## '):
            h = l[3:].strip()
            if h in ('共通', '日本語UI', '英語UI'):
                lang = '' if h == '共通' else h
                in_check = False
            else:
                in_check = h == 'チェックリスト'
            cur = None
            continue
        if l.startswith('### ') and l[4:].strip() in ('原則', 'チェックリスト'):
            in_check = l[4:].strip() == 'チェックリスト'
            cur = None
            continue
        m = RE_FULL.match(l) or RE_SUB.match(l)
        if m:
            cur = {'title': m.group(1), 'strength': m.group(2), 'form': 'full', 'cond': '', 'why': '', 'example': '', 'numbers': '', 'lang': lang}
            items.append(cur)
            continue
        if in_check:
            m = RE_CHECK.match(l)
            if m:
                t = m.group(1)
                cond = ''
                cm = re.search(r'\(条件: (.+)\)$', t)
                if cm:
                    cond, t = cm.group(1), t[:cm.start()]
                items.append({'title': t, 'strength': '必須' if m.group(2) else '推奨', 'form': 'check', 'cond': cond, 'lang': lang})
            continue
        if cur is None or not l.strip():
            continue
        if l.startswith('例: '):
            cur['example'] = l[3:]
        elif l.startswith('数値: '):
            cur['numbers'] = l[4:]
        else:
            parts = l.split(' ／ ')
            for p in parts:
                if p.startswith('条件: '):
                    cur['cond'] = p[4:]
                elif p.startswith('理由: '):
                    cur['why'] = p[4:]
    return title, scope, items


def chips(cond):
    if not cond:
        return '<span class="cond any">条件なし</span>'
    return ''.join(f'<span class="cond">{html.escape(c)}</span>' for c in cond.split('、'))


def card(it, ex, anchor):
    e = html.escape
    pair = ''
    if ex:
        pair = (f'<div class="pair"><figure class="ex ng"><figcaption><b>NG</b> {e(ex.get("ng_caption", ""))}</figcaption><div class="stage">{ex.get("ng", "")}</div></figure>'
                f'<figure class="ex ok"><figcaption><b>OK</b> {e(ex.get("ok_caption", ""))}</figcaption><div class="stage">{ex.get("ok", "")}</div></figure></div>')
    rows = ''
    if it.get('why'):
        rows += f'<p class="why">{e(it["why"])}</p>'
    if it.get('example'):
        rows += f'<p class="meta"><b>例</b> {e(it["example"])}</p>'
    if it.get('numbers'):
        rows += f'<p class="meta"><b>数値</b> {e(it["numbers"])}</p>'
    lang = f'<span class="cond">{e(it["lang"])}</span>' if it.get('lang') else ''
    must = it['strength'] == '必須'
    return (f'<article class="card{" must" if must else ""}" id="{anchor}" data-must="{int(must)}" data-text="{e(it["title"] + " " + it.get("cond", ""))}">'
            f'<div class="head"><span class="strength">{e(it["strength"])}</span>{lang}{chips(it.get("cond", ""))}</div>'
            f'<h3>{e(it["title"])}</h3>{rows}{pair}</article>')


def main():
    examples = json.loads((HERE / 'examples.json').read_text(encoding='utf-8'))
    used, missing = set(), []
    nav, body = [], []
    total = fulls = with_ex = musts = 0
    for gname, names in GROUPS:
        links = []
        for n in names:
            path = REFS / f'{n}.md'
            if not path.exists():
                continue
            title, scope, items = parse(path)
            links.append(f'<a href="#{n}">{html.escape(title)}</a>')
            cards, checks = [], []
            for i, it in enumerate(items):
                total += 1
                musts += it['strength'] == '必須'
                if it['form'] == 'full':
                    fulls += 1
                    ex = examples.get(it['title'])
                    if ex:
                        used.add(it['title'])
                        with_ex += 1
                    else:
                        missing.append(f'{n}.md: {it["title"]}')
                    cards.append(card(it, ex, f'{n}-{i + 1}'))
                elif it['title'] in examples:
                    used.add(it['title'])
                    cards.append(card(it, examples[it['title']], f'{n}-{i + 1}'))
                else:
                    mark = '<span class="strength">必須</span>' if it['strength'] == '必須' else ''
                    cond = f'<span class="cond">{html.escape(it["cond"])}</span>' if it.get('cond') else ''
                    lang = f'<span class="cond">{html.escape(it["lang"])}</span>' if it.get('lang') else ''
                    checks.append(f'<li data-must="{int(it["strength"] == "必須")}" data-text="{html.escape(it["title"])}">{html.escape(it["title"])} {mark}{lang}{cond}</li>')
            sec = f'<section id="{n}"><h2>{html.escape(title)} <small>{html.escape(n)}.md</small></h2><p class="scope">読む場面: {html.escape(scope)}</p>'
            sec += ''.join(cards)
            if checks:
                sec += f'<h3 class="checkh">チェックリスト</h3><ul class="checks">{"".join(checks)}</ul>'
            body.append(sec + '</section>')
        nav.append(f'<div class="navgroup"><span>{html.escape(gname)}</span>{"".join(links)}</div>')
    stale = sorted(set(examples) - used)
    tpl = (HERE / 'template.html').read_text(encoding='utf-8')
    out = (tpl.replace('{{NAV}}', ''.join(nav)).replace('{{BODY}}', ''.join(body))
              .replace('{{COUNTS}}', f'原則 {total}件(うち必須 {musts}件)・図解 {with_ex}/{fulls}件'))
    (HERE / 'index.html').write_text(out, encoding='utf-8')
    print(f'wrote index.html: {total} principles, {with_ex}/{fulls} with examples')
    for m in missing:
        print('図解なし:', m, file=sys.stderr)
    for s in stale:
        print('見出しが一致しない図解:', s, file=sys.stderr)


if __name__ == '__main__':
    main()
