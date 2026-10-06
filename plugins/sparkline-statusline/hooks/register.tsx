import { atom, read, update } from 'claude-code'
import type { Register, SessionContextUsage, SessionRateLimit } from 'claude-code'

import type { CacheStats, RateLimit, Usage } from '../types'

// Desktop-only band. The terminal uses scripts/statusline.py, which has richer prompt_cache data.
const usage = atom({ plugin: 'sparkline-statusline', key: 'usage' } as const, { rateLimits: [] } as Usage)
const EMPTY_CACHE: CacheStats = {
  inputTokens: 0,
  readTokens: 0,
  creationTokens: 0,
  lastResponseAt: null,
  lastHadCache: false,
  ttl: null,
}
const cache = atom({ plugin: 'sparkline-statusline', key: 'cache' } as const, EMPTY_CACHE)

const SPARKS = ' ▁▂▃▄▅▆▇█'
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

const hhmm = (ms: number): string => {
  const d = new Date(ms)
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

const toUsage = (context: SessionContextUsage, rateLimits: SessionRateLimit[]): Usage => ({
  ctxPercent: context.percent,
  rateLimits: rateLimits.map(({ kind, percentUsed, resetsAt }): RateLimit => ({ kind, percentUsed, resetsAt })),
})

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
      const stats = await update($, cache, c => ({
        ...c,
        inputTokens: c.inputTokens + u.input_tokens,
        readTokens: c.readTokens + u.cache_read_input_tokens,
        creationTokens: c.creationTokens + u.cache_creation_input_tokens,
        lastResponseAt: now,
        lastHadCache: u.cache_read_input_tokens + u.cache_creation_input_tokens > 0,
      }))
      expiryTimer?.cancel()
      if (stats.ttl) expiryTimer = $.clock.after(TTL_MS[stats.ttl], () => $.ui.invalidate('ui.render'))
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

    const { Box, Text } = $.ui.resolve(e)
    const u = await read($, usage)
    const c = await read($, cache)
    const now = await $.clock.now()

    const gauge = (label: string, pct: number, suffix?: string) => (
      <Text>
        <Text dimColor>{label}</Text> <Text color={gradient(pct)}>{sparkGauge(pct)}</Text> {Math.round(pct)}%
        {suffix && <Text dimColor> {suffix}</Text>}
      </Text>
    )

    const parts = []
    if (u.ctxPercent !== undefined) parts.push(gauge('ctx', u.ctxPercent))
    const five = u.rateLimits.find(r => r.kind === 'five_hour')
    if (five) parts.push(gauge('5h', five.percentUsed, five.resetsAt && `(reset ${hhmm(Date.parse(five.resetsAt))})`))
    const week = u.rateLimits.find(r => r.kind === 'seven_day')
    if (week) parts.push(gauge('7d', week.percentUsed))

    const total = c.inputTokens + c.readTokens + c.creationTokens
    if (total > 0) {
      const expiresAt = c.ttl && c.lastResponseAt !== null ? c.lastResponseAt + TTL_MS[c.ttl] : null
      const warm = c.lastHadCache && expiresAt !== null && now < expiresAt
      parts.push(
        <Text>
          <Text dimColor>cache</Text>
          {expiresAt !== null &&
            (warm ? (
              <Text>
                {' '}
                <Text color={GREEN}>●</Text> <Text dimColor>~{hhmm(expiresAt)}</Text>
              </Text>
            ) : (
              <Text dimColor> ○</Text>
            ))}{' '}
          {Math.round((c.readTokens / total) * 100)}%
        </Text>,
      )
    }

    if (parts.length === 0) return next(e)

    return (
      <Box flexDirection="row" flexWrap="wrap">
        {parts.map((part, i) => (
          <Text>
            {i > 0 && <Text dimColor> │ </Text>}
            {part}
          </Text>
        ))}
      </Box>
    )
  })
}
