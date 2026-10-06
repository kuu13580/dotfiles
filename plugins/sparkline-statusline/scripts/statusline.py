#!/usr/bin/env python3
"""Pattern 2: Sparkline gauge - vertical block characters"""
import json, sys
from datetime import datetime, timezone
if sys.platform == 'win32':
    sys.stdout.reconfigure(encoding='utf-8')

data = json.load(sys.stdin)

SPARKS = ' ▁▂▃▄▅▆▇█'
R = '\033[0m'
DIM = '\033[2m'
GREEN = '\033[38;2;0;200;80m'
RED = '\033[38;2;255;60;60m'

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

def fmt(label, pct):
    p = round(pct)
    return f'{DIM}{label}{R} {gradient(pct)}{spark_gauge(pct)}{R} {p}%'

def hhmm(epoch):
    return datetime.fromtimestamp(epoch, tz=timezone.utc).astimezone().strftime('%H:%M')

def fmt_cache(pc):
    expires_at = pc.get('expires_at')
    if pc.get('warm') and expires_at is not None:
        s = f'{DIM}cache{R} {GREEN}●{R} {DIM}~{hhmm(expires_at)}{R}'
    else:
        s = f'{DIM}cache ○{R}'
    hit = pc.get('hit_ratio')
    if hit is not None:
        s += f' {round(hit * 100)}%'
    misses = pc.get('misses') or 0
    if misses > 0:
        s += f' {RED}✗{misses}{R}'
        causes = (pc.get('last_miss_cause') or {}).get('causes')
        if causes:
            s += f' {DIM}{",".join(causes)}{R}'
    return s

model = data.get('model', {}).get('display_name', 'Claude')
parts = [model]

ctx = data.get('context_window', {}).get('used_percentage')
if ctx is not None:
    parts.append(fmt('ctx', ctx))

five_hour = data.get('rate_limits', {}).get('five_hour', {})
five = five_hour.get('used_percentage')
if five is not None:
    resets_at = five_hour.get('resets_at')
    if resets_at is not None:
        parts.append(f'{fmt("5h", five)} {DIM}(reset {hhmm(resets_at)}){R}')
    else:
        parts.append(fmt('5h', five))

week = data.get('rate_limits', {}).get('seven_day', {}).get('used_percentage')
if week is not None:
    parts.append(fmt('7d', week))

prompt_cache = data.get('prompt_cache')
if prompt_cache and prompt_cache.get('caching_observed'):
    parts.append(fmt_cache(prompt_cache))

print(f' {DIM}│{R} '.join(parts), end='')
