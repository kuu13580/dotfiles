import { describe, expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'

import { gradient, sparkGauge } from './register'

const PROPS = { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 120, scroll: { offset: 0, bodyRows: 10 }, view: {} }

const bottom = (on: On) => {
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  on('turn.complete', () => ({ text: '' }))
  on('classic.PostModelSwitch', () => ({}))
  on('session.end', (_$, e) => ({ sessionId: e.sessionId }))
  on('ui.render', ($, e) => {
    const { Box } = $.ui.resolve(e)
    return <Box />
  })
}

const feed = async ($: Engine) => {
  await $.session.measure({
    context: { tokens: 62_000, window: 100_000, percent: 62 },
    rateLimits: [
      { kind: 'five_hour', percentUsed: 15, resetsAt: '2026-10-06T09:30:00Z' },
      { kind: 'seven_day', percentUsed: 3 },
    ],
    changed: ['context', 'rateLimits'],
  })
  await $.turn.complete({
    answer: '',
    durationMs: 1,
    isAborted: false,
    turnId: 't1',
    reason: 'answer',
    usage: { model: 'm', input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 90, cache_creation_input_tokens: 0 },
  })
}

const SWITCH = {
  from_model: 'a',
  to_model: 'b',
  requested_model: null,
  source: 'command',
  context_tokens: 0,
  prompt_cache_warm: false,
  cache_ttl: '5m',
  estimated_cache_write_usd: 0,
  pricing: 'catalog',
} as const

const mountBand = ($: Engine, surface: 'terminal' | 'desktop') =>
  $.ui.mount({ plugin: 'sparkline-statusline', surface, component: 'AbovePrompt', props: PROPS })

describe('helpers', () => {
  test('sparkGauge fills by level', () => {
    expect(sparkGauge(0)).toBe('        ')
    expect(sparkGauge(100)).toBe('████████')
    expect(sparkGauge(50)).toBe('████    ')
  })
  test('gradient matches statusline.py', () => {
    expect(gradient(0)).toBe('#00c850')
    expect(gradient(100)).toBe('#ff003c')
  })
})

describe('band', () => {
  test('desktop draws ctx, rate limits and cache hit ratio without TTL', async ($, on) => {
    mock.clock(on, { now: 1_000_000 })
    bottom(on)
    await feed($)
    const ui = await mountBand($, 'desktop')
    expect(await ui.find({ text: /ctx/ })).toBeDefined()
    expect(await ui.find({ text: /reset \d\d:\d\d/ })).toBeDefined()
    expect(await ui.find({ text: /7d/ })).toBeDefined()
    expect(await ui.find({ text: /90%/ })).toBeDefined()
    expect(await ui.find({ text: /●|○/ })).toBeUndefined()
  })

  test('desktop shows warm expiry once TTL is known, then cold after it', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000_000 })
    bottom(on)
    await $.classic.PostModelSwitch(SWITCH)
    await feed($)
    const ui = await mountBand($, 'desktop')
    expect(await ui.find({ text: /●/ })).toBeDefined()
    expect(await ui.find({ text: /~\d\d:\d\d/ })).toBeDefined()
    await clock.advance(5 * 60_000)
    await ui.redraw()
    expect(await ui.find({ text: /○/ })).toBeDefined()
  })

  test('a model switch after a response shows cold until the next response', async ($, on) => {
    mock.clock(on, { now: 1_000_000 })
    bottom(on)
    await $.classic.PostModelSwitch(SWITCH)
    await feed($)
    await $.classic.PostModelSwitch(SWITCH)
    const ui = await mountBand($, 'desktop')
    expect(await ui.find({ text: /○/ })).toBeDefined()
    expect(await ui.find({ text: /●/ })).toBeUndefined()
  })

  test('/clear resets the cache stats', async ($, on) => {
    mock.clock(on)
    bottom(on)
    await feed($)
    await $.session.end({ reason: 'clear', sessionId: 's', resume: { id: 's' } })
    const ui = await mountBand($, 'desktop')
    expect(await ui.find({ text: /cache/ })).toBeUndefined()
    expect(await ui.find({ text: /ctx/ })).toBeDefined()
  })

  test('terminal is left to the command statusline', async ($, on) => {
    mock.clock(on)
    bottom(on)
    await feed($)
    const ui = await mountBand($, 'terminal')
    expect(await ui.find({ text: /ctx/ })).toBeUndefined()
  })
})
