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
        reset_time = datetime.fromtimestamp(resets_at, tz=timezone.utc).astimezone()
        reset_str = reset_time.strftime('%H:%M')
        parts.append(f'{fmt("5h", five)} {DIM}(reset {reset_str}){R}')
    else:
        parts.append(fmt('5h', five))

week = data.get('rate_limits', {}).get('seven_day', {}).get('used_percentage')
if week is not None:
    parts.append(fmt('7d', week))

print(f' {DIM}│{R} '.join(parts), end='')
