import { expect, test } from 'claude-code/testing'

import { split } from './register'

const PANE = {
  plugin: 'md-view',
  component: 'Pane',
  requestId: 'md-view',
  props: {
    title: 'Markdown',
    isFocused: false,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 30 },
    view: {},
  },
} as const

const DOC = '# 見出し\n\n本文\n\n```mermaid\ngraph TD\n  A-->B\n```\n\n後ろ\n'
const ASCII = '┌───┐\n│ A │\n└───┘'
const SVG = '<svg xmlns="http://www.w3.org/2000/svg"><text>A</text></svg>'

function engine(on: any, tools: { leaf: boolean; mmdc: boolean }) {
  on('command.register', () => ({ value: { command: 'md' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_: unknown, e: any) => ({ cwd: e.cwd }))
  on('session.cwd', () => ({ value: '/work' }))
  on('clock.now', () => ({ value: 100000 }))
  on('fs.read', () => ({ value: DOC }))
  on('fs.stat', () => ({ value: { kind: 'file', size: DOC.length, mtimeMs: 1, isSymbolicLink: false } }))
  on('process.run', (_: unknown, e: any) => {
    const cmd = e.argv[0] as 'leaf' | 'mmdc'
    if (!tools[cmd]) throw new Error(`spawn ${cmd} ENOENT`)
    const out = e.argv.includes('--version') ? '1.0.0' : cmd === 'leaf' ? ASCII : SVG
    return { value: { exitCode: 0, stdout: out, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.render', ($: any, e: any) => {
    const { Markdown } = $.ui.resolve(e)
    return <Markdown text={e.props.text} />
  })
}

const RUN = { command: 'md', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 120 } } as const

const REPLY = { plugin: 'md-view', component: 'AssistantMessage', requestId: 'm1', props: { text: DOC, isFirstOfReply: true } } as const

test('ペイン: 端末は leaf の ASCII、デスクトップは SVG', async ($, on) => {
  engine(on, { leaf: true, mmdc: true })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  const r = await $.command.run({ ...RUN, args: 'notes/a.md' })
  expect(r.text).toBe('Markdown ペインで表示: /work/notes/a.md')

  const term = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await term.find({ type: 'Text', text: /│ A │/ })).toBeDefined()
  expect(await term.find({ type: 'Markdown', text: /# 見出し/ })).toBeDefined()
  await term.unmount()

  const desk = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await desk.find({ type: 'Svg' })).toBeDefined()
  expect(await desk.find({ type: 'Markdown', text: /graph TD/ })).toBeUndefined()
  await desk.unmount()
})

test('ペイン: 変換コマンドがなければ mermaid はソースのまま', async ($, on) => {
  engine(on, { leaf: false, mmdc: false })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await $.command.run({ ...RUN, args: '/work/a.md' })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Markdown', text: /```mermaid\ngraph TD/ })).toBeDefined()
    await ui.unmount()
  }
})

test('返答: 端末は ASCII の text フェンス、デスクトップは SVG', async ($, on) => {
  engine(on, { leaf: true, mmdc: true })
  const term = await $.ui.mount({ ...REPLY, surface: 'terminal' })
  const md = await term.find({ type: 'Markdown' })
  expect(md?.text).toMatch(/```text\n┌───┐/)
  expect(md?.text).not.toMatch(/graph TD/)
  await term.unmount()

  const desk = await $.ui.mount({ ...REPLY, surface: 'desktop' })
  expect(await desk.find({ type: 'Svg' })).toBeDefined()
  expect(await desk.find({ type: 'Markdown', text: /# 見出し/ })).toBeDefined()
  await desk.unmount()
})

test('返答: mobile は書き換えずソースのまま', async ($, on) => {
  engine(on, { leaf: true, mmdc: true })
  const mobile = await $.ui.mount({ ...REPLY, surface: 'mobile' })
  expect(await mobile.find({ type: 'Markdown', text: /```mermaid\ngraph TD/ })).toBeDefined()
  expect(await mobile.find({ type: 'Svg' })).toBeUndefined()
  await mobile.unmount()
})

test('返答: mmdc がなければデスクトップは ASCII の text フェンス', async ($, on) => {
  engine(on, { leaf: true, mmdc: false })
  const desk = await $.ui.mount({ ...REPLY, surface: 'desktop' })
  expect(await desk.find({ type: 'Svg' })).toBeUndefined()
  expect(await desk.find({ type: 'Markdown', text: /```text\n┌───┐/ })).toBeDefined()
  await desk.unmount()
})

test('返答: 図にできない surface では入れ方を一度だけ toast で知らせる', async ($, on) => {
  engine(on, { leaf: false, mmdc: true })
  const toasts: string[] = []
  on('ui.toast', (_, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  for (const requestId of ['m1', 'm2']) {
    const term = await $.ui.mount({ ...REPLY, requestId, surface: 'terminal' })
    await term.unmount()
  }
  expect(toasts).toHaveLength(1)
  expect(toasts[0]).toMatch(/@rivolink\/leaf/)

  const desk = await $.ui.mount({ ...REPLY, surface: 'desktop' })
  await desk.unmount()
  expect(toasts).toHaveLength(1)
})

test('split: 他のコードフェンスの中の mermaid は図にしない', () => {
  const nested = '例:\n\n````markdown\n```mermaid\ngraph TD\n```\n````\n'
  expect(split(nested).some(s => s.kind === 'mermaid')).toBe(false)
  expect(split('```ts\nx\n```\n~~~mermaid\nA-->B\n~~~\n後ろ')).toEqual([
    { kind: 'md', text: '```ts\nx\n```\n' },
    { kind: 'mermaid', text: 'A-->B\n' },
    { kind: 'md', text: '\n後ろ' },
  ])
  expect(split('```mermaid\ngraph TD\n').some(s => s.kind === 'mermaid')).toBe(false)
})

test('追従: pane が開いている時だけ Write した .md を読み込む', async ($, on) => {
  engine(on, { leaf: true, mmdc: true })
  let open = false
  on('ui.panes', () => ({
    value: open ? [{ id: 'md-view', title: 'Markdown', isShown: true, isFocused: false, isPlaced: true }] : [],
  }))
  on('tool.call', () => ({ result: {} as any }))
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  // 引数を直接書くと tool のユニオン型の展開が深すぎて tsc が止まるため any で呼ぶ
  const write = (file_path: string) => ($.tool.call as any)({ tool: 'Write', file_path, content: DOC })

  await write('/work/closed.md')
  const before = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await before.find({ type: 'Text', text: /未選択/ })).toBeDefined()
  await before.unmount()

  open = true
  await write('/work/open.md')
  const after = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await after.find({ type: 'Text', text: '/work/open.md' })).toBeDefined()
  await after.unmount()
})

const BASE = { id: 'intro', text: 'base', scope: 'shared' } as const
const hinted = async ($: any, surfaces: string[], traits: string[] = []) =>
  (await $.prompt.compose({ model: 'm', promptModel: 'm', tools: [], outputStyle: null, surfaces, traits })).sections.some((s: any) => s.id === 'md-view:mermaid')

test('システムプロンプト: 図にできる surface がある時だけ mermaid の一節を足す', async ($, on) => {
  engine(on, { leaf: false, mmdc: true })
  on('prompt.compose', () => ({ sections: [BASE] }))
  expect(await hinted($, ['desktop'])).toBe(true)
  expect(await hinted($, ['terminal'])).toBe(false)
  expect(await hinted($, ['mobile'])).toBe(false)
  expect(await hinted($, [])).toBe(false)
  expect(await hinted($, ['desktop'], ['bare'])).toBe(false)
})

test('システムプロンプト: leaf があれば端末でも足す', async ($, on) => {
  engine(on, { leaf: true, mmdc: false })
  on('prompt.compose', () => ({ sections: [BASE] }))
  expect(await hinted($, ['terminal'])).toBe(true)
})

test('引数なしで対象がなければ案内だけ返す', async ($, on) => {
  engine(on, { leaf: true, mmdc: true })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  const r = await $.command.run({ ...RUN, args: '' })
  expect(r.text).toMatch(/\/md <path>/)
})
