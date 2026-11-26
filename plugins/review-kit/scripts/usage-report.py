#!/usr/bin/env python3
"""review-kit のスキル実行で使ったトークン量を、セッションの記録から集計する。

Usage: python3 usage-report.py [--session <session.jsonl>] [--all] [--log] [--skill <name>]
  既定: 最後に review-kit のスキルを呼んだ時点から記録の最後までを1件として出す
  --skill: そのスキルを最後に呼んだ時点から記録の最後までを1件とする (途中で呼んだ別のスキルの分も含める)
  --all: このセッションで review-kit のスキルを呼んだ回ごとに出す
  --log: 結果を ~/.claude/review-kit/usage.tsv に追記する (傾向を見るため)
"""
import argparse, glob, json, os, re, sys
from datetime import datetime

SKILLS = ("self-review", "review-response", "pr-review", "check-review-validity")
KEYS = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")


def find_session():
    cwd = os.getcwd()
    proj = os.path.expanduser("~/.claude/projects/" + re.sub(r"[^A-Za-z0-9]", "-", cwd))
    files = glob.glob(os.path.join(proj, "*.jsonl")) or glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl"))
    if not files:
        sys.exit("セッションの記録が見つかりません。--session で指定してください。")
    return max(files, key=os.path.getmtime)


def load(path):
    rows = []
    with open(path) as f:
        for line in f:
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return rows


def usage_of(rows):
    """同じ応答 (message.id) が複数行に分かれて記録されるため、id ごとに1回だけ数える。"""
    seen, total = set(), dict.fromkeys(KEYS, 0)
    for r in rows:
        msg = r.get("message") or {}
        if r.get("type") != "assistant" or not msg.get("usage") or msg.get("id") in seen:
            continue
        seen.add(msg.get("id"))
        for k in KEYS:
            total[k] += msg["usage"].get(k) or 0
    return total


def skill_name(text):
    for s in SKILLS:
        if re.search(r"(review-kit:)?" + re.escape(s) + r"\b", text):
            return s
    return None


def invocations(rows):
    """review-kit のスキルが呼ばれた時刻と名前。スラッシュコマンドと Skill ツールの両方を拾う。"""
    out = []
    for r in rows:
        ts, msg = r.get("timestamp"), r.get("message") or {}
        content = msg.get("content")
        if r.get("type") == "user" and isinstance(content, str) and "<command-name>" in content:
            m = re.search(r"<command-name>/?([^<]+)</command-name>", content)
            if m and m.group(1).startswith("review-kit:") and skill_name(m.group(1)):
                out.append((ts, skill_name(m.group(1))))
        if r.get("type") == "assistant" and isinstance(content, list):
            for c in content:
                if c.get("type") == "tool_use" and c.get("name") == "Skill":
                    name = (c.get("input") or {}).get("skill", "")
                    if name.startswith("review-kit:") or name in SKILLS:
                        if skill_name(name):
                            out.append((ts, skill_name(name)))
    return out


def subagent_rows(session_path):
    d = os.path.join(os.path.splitext(session_path)[0], "subagents")
    agents = []
    for p in glob.glob(os.path.join(d, "agent-*.jsonl")):
        rows = load(p)
        stamps = [r.get("timestamp") for r in rows if r.get("timestamp")]
        if stamps:
            agents.append((min(stamps), rows))
    return agents


def fmt(n):
    return f"{n / 1000:.0f}k" if n >= 1000 else str(n)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--session")
    scope = ap.add_mutually_exclusive_group()
    scope.add_argument("--all", action="store_true")
    scope.add_argument("--skill")
    ap.add_argument("--log", action="store_true")
    a = ap.parse_args()
    if a.skill:
        a.skill = a.skill.removeprefix("review-kit:")
        if a.skill not in SKILLS:
            sys.exit(f"--skill は {', '.join(SKILLS)} のいずれかを指定してください。")
    path = a.session or find_session()
    rows = load(path)
    runs = invocations(rows)
    if not runs:
        sys.exit("このセッションでは review-kit のスキルが呼ばれていません。")
    # 同じ時刻の重複 (コマンドで呼ばれたあと Skill ツールでも呼ばれた等) を除く
    runs = sorted(dict(runs).items())
    agents = subagent_rows(path)
    windows = [(ts, name, runs[i + 1][0] if i + 1 < len(runs) else "9999") for i, (ts, name) in enumerate(runs)]
    if a.skill:
        # review-response が中で self-review を呼ぶと区間が分かれ、親の前半が落ちるため
        starts = [ts for ts, name in runs if name == a.skill]
        if not starts:
            sys.exit(f"このセッションでは {a.skill} が呼ばれていません。")
        windows = [(starts[-1], a.skill, "9999")]
    elif not a.all:
        windows = windows[-1:]
    lines = []
    for start, name, end in windows:
        main_u = usage_of([r for r in rows if start <= (r.get("timestamp") or "") < end])
        sub = [rs for ts, rs in agents if start <= ts < end]
        sub_u = usage_of([r for rs in sub for r in rs])
        tot = {k: main_u[k] + sub_u[k] for k in KEYS}
        fresh = tot["input_tokens"] + tot["cache_creation_input_tokens"] + tot["output_tokens"]
        line = (f"{name} ({start[:16].replace('T', ' ')} UTC): 合計 新規 {fmt(fresh)} + キャッシュ読込 {fmt(tot['cache_read_input_tokens'])} / "
                f"出力 {fmt(tot['output_tokens'])} / サブエージェント {len(sub)} 体 (新規 {fmt(sub_u['input_tokens'] + sub_u['cache_creation_input_tokens'] + sub_u['output_tokens'])})")
        lines.append(line)
        if a.log:
            log = os.path.expanduser("~/.claude/review-kit/usage.tsv")
            os.makedirs(os.path.dirname(log), exist_ok=True)
            new = not os.path.exists(log)
            with open(log, "a") as f:
                if new:
                    f.write("logged_at\tstarted_at\tskill\tcwd\tinput\tcache_write\tcache_read\toutput\tsubagents\n")
                f.write("\t".join(map(str, [datetime.now().isoformat(timespec="seconds"), start, name, os.getcwd(),
                                            tot["input_tokens"], tot["cache_creation_input_tokens"],
                                            tot["cache_read_input_tokens"], tot["output_tokens"], len(sub)])) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
