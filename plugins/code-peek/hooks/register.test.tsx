import { describe, expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import { linkify, parseHref, rankCandidates, topOf } from './register'

const FILES: Record<string, string> = {
  '/repo/src/app/api.ts': Array.from({ length: 100 }, (_, i) => `line ${i + 1}`).join('\n'),
  '/repo/src/lib/api.ts': 'short\n',
}

const engine = (on: On) => {
  on('fs.exists', (_$, e) => ({ value: e.path in FILES }))
  on('fs.read', (_$, e) => {
    const text = FILES[e.path]
    if (text === undefined) throw new Error('ENOENT')
    return { value: text }
  })
  on('process.run', (_$, e) => {
    const args = e.argv.slice(1).join(' ')
    const ok = (stdout: string, exitCode = 0) => ({ value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } })
    if (args === 'rev-parse --show-toplevel') return ok('/repo\n')
    if (args.startsWith('ls-files')) {
      const want = e.argv[e.argv.indexOf('--') + 1]!
      const files = ['src/app/api.ts', 'src/lib/api.ts', 'README.md'].filter(f => f === want || f.endsWith(`/${want}`))
      return ok(files.map(f => `${f}\0`).join(''))
    }
    return ok('', 1)
  })
  on('ui.open', () => ({ value: { isPlaced: true as const } }))
  on('ui.render', ($, e) => {
    const { Box } = $.ui.resolve(e)
    return <Box />
  })
}

describe('linkify', () => {
  test('links bare and backticked refs', () => {
    const r = linkify('see src/a.ts:12 and `b.tsx:3-5`')
    expect(r.text).toBe('see [src/a.ts:12](file:src/a.ts#L12) and [`b.tsx:3-5`](file:b.tsx#L3-L5)')
    expect(r.hrefs).toEqual(['file:src/a.ts#L12', 'file:b.tsx#L3-L5'])
  })
  test('links GitHub-style refs', () => {
    const r = linkify('see src/a.ts#L12 and `b.tsx#L3-L5`')
    expect(r.text).toBe('see [src/a.ts#L12](file:src/a.ts#L12) and [`b.tsx#L3-L5`](file:b.tsx#L3-L5)')
    expect(r.hrefs).toEqual(['file:src/a.ts#L12', 'file:b.tsx#L3-L5'])
  })
  test('leaves code fences, links, urls and mixed inline code alone', () => {
    const src = '```\nfoo.ts:1\n```\n[x.ts:2](https://e.com) https://h.com/a.ts:3 `run a.ts:4 now`'
    expect(linkify(src)).toEqual({ text: src, hrefs: [] })
  })
  test('parseHref round-trips', () => {
    expect(parseHref('file:src/a.ts#L12')).toEqual({ path: 'src/a.ts', line: 12 })
    expect(parseHref('file:b.ts#L3-L5')).toEqual({ path: 'b.ts', line: 3, endLine: 5 })
    expect(parseHref('https://x')).toBe(undefined)
  })
})

describe('rankCandidates', () => {
  test('prefers files long enough, then changed files', () => {
    const counts = new Map([['a/x.ts', 10], ['b/x.ts', 200], ['c/x.ts', 300]])
    expect(rankCandidates(['a/x.ts', 'b/x.ts', 'c/x.ts'], new Set(['c/x.ts']), counts, 50)).toEqual(['c/x.ts'])
    expect(rankCandidates(['a/x.ts', 'b/x.ts', 'c/x.ts'], new Set(), counts, 50)).toEqual(['b/x.ts', 'c/x.ts'])
  })
})

describe('topOf', () => {
  test('centres, then clamps to the file', () => {
    expect(topOf({ center: 50 }, 100, 29)).toBe(35)
    expect(topOf({ center: 3 }, 100, 29)).toBe(0)
    expect(topOf({ center: 99 }, 100, 29)).toBe(71)
    expect(topOf({ top: 500 }, 100, 29)).toBe(71)
    expect(topOf({ top: 0 }, 10, 29)).toBe(0)
  })
})

describe('blank lines', () => {
  test('stay as rows so code lines up with the numbers', async ($, on) => {
    engine(on)
    FILES['/repo/blank.ts'] = '\n\nconst a = 1\n  \n\n'
    const pane = await $.ui.mount({
      plugin: 'code-peek',
      surface: 'terminal',
      component: 'Pane',
      requestId: 'code-peek',
      viewport: { columns: 100, rows: 40 },
      props: { title: 'blank.ts:3', isFocused: false, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 30 }, view: {} },
    })
    const msg = await $.ui.mount({
      plugin: 'code-peek',
      surface: 'terminal',
      component: 'AssistantMessage',
      viewport: { columns: 120, rows: 40, isFullscreen: true },
      props: { text: 'see /repo/blank.ts:3', isFirstOfReply: true },
    })
    await msg.press({ key: 'code-peek-refs', link: { href: 'file:/repo/blank.ts#L3' } })
    const source = String((await pane.find({ type: 'Code' }))?.props.source)
    expect(source.split('\n').length).toBe(6)
    expect(source.startsWith('\u00a0\n')).toBe(true)
  })
})

describe('pane', () => {
  test('a click on a basename ref resolves it, shows the file centred on the line under a fixed header', async ($, on) => {
    engine(on)
    const msg = await $.ui.mount({
      plugin: 'code-peek',
      surface: 'terminal',
      component: 'AssistantMessage',
      viewport: { columns: 120, rows: 40, isFullscreen: true },
      props: { text: 'the retry lives at `api.ts:50`', isFirstOfReply: true },
    })
    const pane = await $.ui.mount({
      plugin: 'code-peek',
      surface: 'terminal',
      component: 'Pane',
      requestId: 'code-peek',
      viewport: { columns: 100, rows: 40 },
      props: { title: 'api.ts:50', isFocused: false, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 30 }, view: {} },
    })
    await msg.press({ key: 'code-peek-refs', link: { href: 'file:api.ts#L50' } })
    expect(await pane.find({ text: /^ src\/app\/api\.ts:50  \(36-64 \/ 100\)/ })).toBeDefined()
    expect(await pane.find({ type: 'Text', text: /^   36\n   37\n/ })).toBeDefined()
    expect((await pane.find({ type: 'Text', text: /^▌  50$/ }))?.props.color).toBe('yellow')
    expect((await pane.find({ type: 'Code' }))?.props.startLine).toBe(undefined)
  })

  test('outside the fullscreen terminal the message is left to the engine', async ($, on) => {
    engine(on)
    const msg = await $.ui.mount({
      plugin: 'code-peek',
      surface: 'terminal',
      component: 'AssistantMessage',
      viewport: { columns: 120, rows: 40, isFullscreen: false },
      props: { text: 'at `api.ts:50`', isFirstOfReply: true },
    })
    expect(await msg.find({ key: 'code-peek-refs' })).toBe(undefined)
  })
})
