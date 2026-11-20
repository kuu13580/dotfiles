#!/usr/bin/env python3
"""Pattern 2: Sparkline gauge - vertical block characters"""
import json, os, re, sys, time
from datetime import datetime, timezone
if sys.platform == 'win32':
    sys.stdout.reconfigure(encoding='utf-8')

data = json.load(sys.stdin)

SPARKS = ' ▁▂▃▄▅▆▇█'
CIRCLES = '○◔◑◕●'
R = '\033[0m'
DIM = '\033[2m'
GREEN = '\033[38;2;0;200;80m'
RED = '\033[38;2;255;0;60m'
WEEK_SECONDS = 7 * 24 * 3600
PACE_THRESHOLD = 5

def gradient(pct):
    if pct < 50:
        r = int(pct * 5.1)
        return f'\033[38;2;{r};200;80m'
    else:
        g = int(200 - (pct - 50) * 4)
        return f'\033[38;2;255;{max(g, 0)};60m'

def spark_gauge(pct, width=8):
    pct = min(max(pct, 0), 100)
    level = pct / 100
    gauge = ''
    for i in range(width):
        seg_start = i / width
        seg_end = (i + 1) / width
        if level >= seg_end:
            gauge += SPARKS[8]
        elif level <= seg_start:
            gauge += SPARKS[0]
        else:
            frac = (level - seg_start) / (seg_end - seg_start)
            gauge += SPARKS[int(frac * 8)]
    return gauge

def circle(pct):
    return CIRCLES[min(int(min(max(pct, 0), 100) / 25 + 0.5), 4)]

def fmt(label, pct, compact):
    gauge = circle(pct) if compact else spark_gauge(pct)
    return f'{DIM}{label}{R} {gradient(pct)}{gauge}{R} {round(pct)}%'

def hhmm(epoch):
    return datetime.fromtimestamp(epoch, tz=timezone.utc).astimezone().strftime('%H:%M')

def pace_diff(used, resets_at):
    elapsed = min(max(1 - (resets_at - time.time()) / WEEK_SECONDS, 0), 1) * 100
    return round(used - elapsed)

def fmt_pace(diff):
    text = f'▲+{diff}pt' if diff > 0 else f'▼{diff}pt' if diff < 0 else '±0pt'
    if diff > PACE_THRESHOLD:
        return f'{RED}{text}{R}'
    if diff < -PACE_THRESHOLD:
        return f'{GREEN}{text}{R}'
    return text

def fmt_cache(pc):
    expires_at = pc.get('expires_at')
    if pc.get('warm') and expires_at is not None:
        return f'{DIM}cache{R} {GREEN}●{R} {DIM}~{hhmm(expires_at)}{R}'
    return f'{DIM}cache ○{R}'

def render(compact):
    parts = [(data.get('model') or {}).get('display_name', 'Claude')]

    ctx = (data.get('context_window') or {}).get('used_percentage')
    if ctx is not None:
        parts.append(fmt('ctx', ctx, compact))

    five_hour = (data.get('rate_limits') or {}).get('five_hour', {})
    five = five_hour.get('used_percentage')
    if five is not None:
        resets_at = five_hour.get('resets_at')
        reset = f' {DIM}(reset {hhmm(resets_at)}){R}' if resets_at is not None else ''
        parts.append(fmt('5h', five, compact) + reset)

    seven_day = (data.get('rate_limits') or {}).get('seven_day', {})
    week = seven_day.get('used_percentage')
    if week is not None:
        week_resets_at = seven_day.get('resets_at')
        pace = f' {fmt_pace(pace_diff(week, week_resets_at))}' if week_resets_at is not None else ''
        parts.append(fmt('7d', week, compact) + pace)

    prompt_cache = data.get('prompt_cache')
    if prompt_cache and prompt_cache.get('caching_observed'):
        parts.append(fmt_cache(prompt_cache))

    return f' {DIM}│{R} '.join(parts)

# Claude Code may draw notices at the right end of the row, so keep a margin.
MARGIN = 4
line = render(False)
columns = os.environ.get('COLUMNS', '')
if columns.isdigit() and len(re.sub(r'\033\[[0-9;]*m', '', line)) > int(columns) - MARGIN:
    line = render(True)
print(line, end='')
