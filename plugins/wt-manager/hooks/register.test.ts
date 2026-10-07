import { describe, expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'

const result = (exitCode: number, stdout = '', stderr = '') => ({
  value: { exitCode, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false },
})

const engine = (on: On, opts: { toplevel?: string; editorExit?: number } = {}) => {
  const launched: string[][] = []
  const store = new Map<string, unknown>()
  on('session.cwd', () => ({ value: '/wt/feature/sub' }))
  on('process.run', (_$, e) => {
    if (e.argv[0] === 'git') return opts.toplevel ? result(0, `${opts.toplevel}\n`) : result(128, '', 'not a git repository')
    launched.push([...e.argv])
    return result(opts.editorExit ?? 0, '', opts.editorExit ? 'boom' : '')
  })
  on('store.get', (_$, e) => ({ value: store.get(e.key) }))
  on('store.set', (_$, e) => {
    store.set(e.key, e.value)
    return { value: undefined }
  })
  on('ui.toast', () => ({ value: undefined }))
  return launched
}

describe('/open', () => {
  test('opens the worktree root with the given editor', async ($, on) => {
    const launched = engine(on, { toplevel: '/wt/feature' })
    const r = await $.command.run({ command: 'open', args: 'zed' })
    expect(r.text ?? '').toBe('')
    expect(launched).toEqual([['zed', '/wt/feature']])
  })

  test('reuses the last editor, defaulting to code', async ($, on) => {
    const launched = engine(on, { toplevel: '/wt/feature' })
    await $.command.run({ command: 'open', args: '' })
    await $.command.run({ command: 'open', args: 'zed' })
    await $.command.run({ command: 'open', args: '' })
    expect(launched.map(a => a[0])).toEqual(['code', 'zed', 'zed'])
  })

  test('falls back to cwd outside a git repository', async ($, on) => {
    const launched = engine(on)
    await $.command.run({ command: 'open', args: 'code' })
    expect(launched).toEqual([['code', '/wt/feature/sub']])
  })

  test('rejects an unknown editor without launching', async ($, on) => {
    const launched = engine(on, { toplevel: '/wt/feature' })
    const r = await $.command.run({ command: 'open', args: 'vim' })
    expect(r.text).toContain('使い方')
    expect(launched).toEqual([])
  })

  test('reports a failed launch and keeps the previous editor', async ($, on) => {
    const launched = engine(on, { toplevel: '/wt/feature', editorExit: 1 })
    const r = await $.command.run({ command: 'open', args: 'zed' })
    expect(r.text).toContain('exit 1')
    await $.command.run({ command: 'open', args: '' })
    expect(launched.map(a => a[0])).toEqual(['zed', 'code'])
  })
})
