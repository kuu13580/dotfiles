import { atom, read, update } from 'claude-code'
import type { Register, SessionContextUsage, SessionRateLimit } from 'claude-code'

import type { CacheState, RateLimit, Usage } from '../types'

// Desktop-only band. The terminal uses scripts/statusline.py, which has richer prompt_cache data.
const usage = atom({ plugin: 'sparkline-statusline', key: 'usage' } as const, { rateLimits: [] } as Usage)
const EMPTY_CACHE: CacheState = { lastResponseAt: null, lastHadCache: false, ttl: null }
const cache = atom({ plugin: 'sparkline-statusline', key: 'cache' } as const, EMPTY_CACHE)

const SPARKS = ' ▁▂▃▄▅▆▇█'
const CIRCLES = '○◔◑◕●'
const GREEN = '#00c850'
const TTL_MS = { '5m': 5 * 60_000, '1h': 60 * 60_000 }

export const gradient = (pct: number): string => {
  const hex = (n: number) => Math.max(0, Math.min(255, Math.trunc(n))).toString(16).padStart(2, '0')
  return pct < 50 ? `#${hex(pct * 5.1)}c850` : `#ff${hex(200 - (pct - 50) * 4)}3c`
}

export const sparkGauge = (pct: number, width = 8): string => {
  const level = Math.min(Math.max(pct, 0), 100) / 100
  let gauge = ''
  for (let i = 0; i < width; i++) {
    const start = i / width
    const end = (i + 1) / width
    if (level >= end) gauge += SPARKS[8]
    else if (level <= start) gauge += SPARKS[0]
    else gauge += SPARKS[Math.trunc(((level - start) / (end - start)) * 8)]
  }
  return gauge
}

export const circle = (pct: number): string =>
  CIRCLES[Math.min(Math.trunc(Math.min(Math.max(pct, 0), 100) / 25 + 0.5), 4)] ?? CIRCLES[0]!

const hhmm = (ms: number): string => {
  const d = new Date(ms)
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

const toUsage = (context: SessionContextUsage, rateLimits: SessionRateLimit[]): Usage => ({
  ctxPercent: context.percent,
  rateLimits: rateLimits.map(({ kind, percentUsed, resetsAt }): RateLimit => ({ kind, percentUsed, resetsAt })),
})

type Piece = { text: string; color?: string; dim?: boolean }

export const register: Register = on => {
  let expiryTimer: { cancel: () => void } | undefined

  on('session.start', async ($, e, next) => {
    const { context, rateLimits } = await $.session.usage()
    await update($, usage, () => toUsage(context, rateLimits))
    return next(e)
  })

  on('session.measure', async ($, e, next) => {
    await update($, usage, () => toUsage(e.context, e.rateLimits))
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined && e.usage) {
      const u = e.usage
      const now = await $.clock.now()
      const state = await update($, cache, c => ({
        ...c,
        lastResponseAt: now,
        lastHadCache: u.cache_read_input_tokens + u.cache_creation_input_tokens > 0,
      }))
      expiryTimer?.cancel()
      if (state.ttl) expiryTimer = $.clock.after(TTL_MS[state.ttl], () => $.ui.invalidate('ui.render'))
    }
    return result
  })

  // A model switch forfeits the cached prefix, so stay cold until the next response.
  on('classic.PostModelSwitch', async ($, e, next) => {
    expiryTimer?.cancel()
    await update($, cache, c => ({ ...c, ttl: e.cache_ttl, lastHadCache: false }))
    return next(e)
  })

  // /clear and resume keep the process but start another conversation, with no session.start.
  on('session.end', async ($, e, next) => {
    if (e.reason === 'clear' || e.reason === 'resume') {
      expiryTimer?.cancel()
      await update($, cache, c => ({ ...EMPTY_CACHE, ttl: c.ttl }))
    }
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.surface === 'terminal' || e.props.hasSurvey) return next(e)

    const u = await read($, usage)
    const c = await read($, cache)
    const now = await $.clock.now()
    const five = u.rateLimits.find(r => r.kind === 'five_hour')
    const week = u.rateLimits.find(r => r.kind === 'seven_day')

    const gauge = (label: string, pct: number, compact: boolean): Piece[] => [
      { text: label, dim: true },
      { text: ' ' },
      { text: compact ? circle(pct) : sparkGauge(pct), color: gradient(pct) },
      { text: ` ${Math.round(pct)}%` },
    ]

    const segments = (compact: boolean): Piece[][] => {
      const list: Piece[][] = []
      if (u.ctxPercent !== undefined) list.push(gauge('ctx', u.ctxPercent, compact))
      if (five) {
        const reset: Piece[] = five.resetsAt ? [{ text: ` (reset ${hhmm(Date.parse(five.resetsAt))})`, dim: true }] : []
        list.push([...gauge('5h', five.percentUsed, compact), ...reset])
      }
      if (week) list.push(gauge('7d', week.percentUsed, compact))
      if (c.ttl && c.lastResponseAt !== null) {
        const expiresAt = c.lastResponseAt + TTL_MS[c.ttl]
        list.push(
          c.lastHadCache && now < expiresAt
            ? [{ text: 'cache', dim: true }, { text: ' ' }, { text: '●', color: GREEN }, { text: ` ~${hhmm(expiresAt)}`, dim: true }]
            : [{ text: 'cache ○', dim: true }],
        )
      }
      return list
    }

    const width = (list: Piece[][]) =>
      list.reduce((sum, pieces) => sum + pieces.reduce((n, p) => n + p.text.length, 0), 0) + (list.length - 1) * 3
    const full = segments(false)
    if (full.length === 0) return next(e)
    const row = width(full) > e.props.bodyColumns ? segments(true) : full

    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="row" flexWrap="wrap">
        {row.map((pieces, i) => (
          <Text>
            {i > 0 && <Text dimColor> │ </Text>}
            {pieces.map(p => (
              <Text color={p.color} dimColor={p.dim}>
                {p.text}
              </Text>
            ))}
          </Text>
        ))}
      </Box>
    )
  })
}
