import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, RenderChildren } from 'claude-code'

import type { MdSegment, MdView } from '../types'

const PANE = 'md-view'
const view = atom(
  { plugin: 'md-view', key: 'view' } as const,
  { mode: 'builtin', follow: true, segments: [] } as MdView,
  { shape: 'view-1' },
)

const MERMAID_HINT = {
  id: 'md-view:mermaid',
  scope: 'session',
  text: [
    '# Diagrams',
    'Fenced ```mermaid blocks in your replies are rendered as diagrams in this session.',
    'Use one when a diagram explains faster than prose, such as a flow, an architecture, a state transition or a sequence.',
    'Do not add diagrams to short answers or where they repeat what the text already says.',
  ].join('\n'),
} as const

const FENCE_OPEN = /^(`{3,}|~{3,})[ \t]*([^\s`]*)/
const isClose = (line: string, fence: string) => {
  const m = /^(`{3,}|~{3,})[ \t]*$/.exec(line)
  return !!m && m[1]![0] === fence[0] && m[1]!.length >= fence.length
}
// leaf の出力や md に混ざる制御文字は Text/Markdown が受け付けないため落とす
const sanitize = (s: string) =>
  s.replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, '').replace(/[\x00-\x08\x0b-\x1f\x7f]/g, '')

let lastCols = 80
let loadedCols = 0
let loadedMtime = 0

// 未導入なら30秒おきに確かめ直し、後から入れたコマンドを reload なしで拾う
const available = new Map<string, { ok: boolean; at: number }>()
async function has($: EngineInterface, cmd: string) {
  const now = await $.clock.now()
  const known = available.get(cmd)
  if (known && (known.ok || now - known.at < 30000)) return known.ok
  let ok = false
  try {
    ok = (await $.process.run([cmd, '--version'], { timeoutMs: 10000 })).exitCode === 0
  } catch {
    ok = false
  }
  available.set(cmd, { ok, at: now })
  return ok
}

// ストリーミング中は同じ図の描画が重なるため実行中の変換を共有する。
// 失敗(空文字)を残し続けると同じ図が以後ずっとソースのままになるため、30 秒で作り直す
const cache = new Map<string, { value: Promise<string>; failedAt?: number }>()
async function cached($: EngineInterface, key: string, make: () => Promise<string>) {
  const now = await $.clock.now()
  const hit = cache.get(key)
  if (hit && (hit.failedAt === undefined || now - hit.failedAt < 30000)) return hit.value
  if (cache.size > 200) cache.clear()
  const entry: { value: Promise<string>; failedAt?: number } = { value: make().catch(() => '') }
  cache.set(key, entry)
  const value = await entry.value
  if (!value) entry.failedAt = await $.clock.now()
  return value
}

async function leafPlain($: EngineInterface, args: { path?: string; stdin?: string; cols?: number }) {
  const argv = ['leaf', '--inline', `plain:${Math.max(20, args.cols ?? lastCols)}`]
  if (args.path) argv.push(args.path)
  const r = await $.process.run(argv, { stdin: args.stdin, timeoutMs: 15000 })
  if (r.exitCode !== 0) throw new Error(sanitize(r.stderr).trim() || `leaf exit ${r.exitCode}`)
  return sanitize(r.stdout).replace(/\s+$/, '')
}

const toAscii = async ($: EngineInterface, source: string, cols: number) =>
  (await has($, 'leaf'))
    ? cached($, `ascii:${cols}\n${source}`, () => leafPlain($, { stdin: '```mermaid\n' + source + '```\n', cols }))
    : ''

// Desktop は mermaid を自前で図にするため、端末に leaf があるときだけ md-view が描く
async function canDraw($: EngineInterface, surfaces: readonly string[]) {
  if (surfaces.includes('desktop')) return true
  return surfaces.includes('terminal') && (await has($, 'leaf'))
}

const INSTALL_HINT =
  'leaf が見つからないため mermaid をソースのまま表示しています。npm install -g @rivolink/leaf などで図になります (他の入れ方は md-view の README)'
let hinted = false

async function hintInstall($: EngineInterface) {
  if (hinted || (await has($, 'leaf'))) return
  hinted = true
  $.ui.toast(INSTALL_HINT, { timeoutMs: 10000 })
}

// 他のコードフェンス(````markdown の例など)の中にある mermaid は図にしない
export function split(raw: string): MdSegment[] {
  const lines = raw.split('\n')
  const offsets: number[] = []
  let pos = 0
  for (const line of lines) {
    offsets.push(pos)
    pos += line.length + 1
  }
  const segments: MdSegment[] = []
  let at = 0
  let i = 0
  while (i < lines.length) {
    const open = FENCE_OPEN.exec(lines[i]!)
    if (!open) {
      i++
      continue
    }
    const fence = open[1]!
    let close = i + 1
    while (close < lines.length && !isClose(lines[close]!, fence)) close++
    if (close >= lines.length) break
    if (open[2] === 'mermaid') {
      const start = offsets[i]!
      if (start > at) segments.push({ kind: 'md', text: raw.slice(at, start) })
      segments.push({ kind: 'mermaid', text: raw.slice(offsets[i + 1], offsets[close]) })
      at = offsets[close]! + lines[close]!.length
    }
    i = close + 1
  }
  if (at < raw.length) segments.push({ kind: 'md', text: raw.slice(at) })
  return segments
}

async function absolute($: EngineInterface, path: string) {
  if (path.startsWith('/')) return path
  const cwd = await $.session.cwd()
  return `${cwd.replace(/\/$/, '')}/${path.replace(/^\.\//, '')}`
}

async function load($: EngineInterface, path?: string) {
  const current = await read($, view)
  const target = path ?? current.path
  if (!target) return
  try {
    const stat = await $.fs.stat(target)
    const raw = sanitize(await $.fs.read(target))
    let segments = split(raw)
    let note: string | undefined
    if (current.mode === 'leaf') {
      if (await has($, 'leaf')) segments = [{ kind: 'pre', text: await leafPlain($, { path: target }) }]
      else note = 'leaf が見つからないため組込み描画で表示'
    }
    loadedMtime = stat.mtimeMs
    loadedCols = lastCols
    await update($, view, v => ({ ...v, path: target, segments, note }))
  } catch (err) {
    await update($, view, v => ({ ...v, path: target, segments: [], note: `読み込めません: ${String(err).slice(0, 300)}` }))
  }
}

const isPaneOpen = async ($: EngineInterface) => (await $.ui.panes()).some(p => p.id === PANE)

async function follow($: EngineInterface, path: string) {
  if (/\.(md|markdown)$/i.test(path) && (await read($, view)).follow && (await isPaneOpen($))) await load($, path)
}

const open = ($: EngineInterface) => $.ui.open({ id: PANE, title: 'Markdown' })

// 端末の mermaid は leaf の ASCII 図にする。端末以外は surface 自身の描画に任せてソースのまま渡す
async function drawSegments($: EngineInterface, e: any, segments: MdSegment[], cols: number) {
  const { Box, Text, Markdown } = $.ui.resolve(e) as any
  const out: RenderChildren[] = []
  for (const [i, s] of segments.entries()) {
    if (s.kind === 'md') {
      out.push(<Markdown key={`s${i}`} text={s.text} />)
      continue
    }
    const text = s.kind === 'pre' ? s.text : e.surface === 'terminal' ? await toAscii($, s.text, cols) : ''
    if (!text) {
      out.push(<Markdown key={`s${i}`} text={'```mermaid\n' + s.text + '```'} />)
    } else if (e.surface === 'terminal') {
      out.push(
        <Box key={`s${i}`} flexDirection="column">
          {text.split('\n').map(line => (
            <Text wrap="truncate-end">{line || ' '}</Text>
          ))}
        </Box>,
      )
    } else {
      out.push(<Markdown key={`s${i}`} text={'```text\n' + text + '\n```'} />)
    }
  }
  return out
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'md',
      description: 'Markdown をペインで表示(引数なし: 直前に表示・追従した .md)',
      argumentHint: '[path]',
    })
    // ファイルの更新とペイン幅の変化を拾って描き直す
    $.clock.every(1500, async () => {
      const { path } = await read($, view)
      if (!path || !(await isPaneOpen($))) return
      try {
        const stat = await $.fs.stat(path)
        if (stat.mtimeMs !== loadedMtime || lastCols !== loadedCols) await load($)
      } catch {
        // 削除・移動中は次の周期で拾う
      }
    })
    return next(e)
  })

  on('prompt.compose', async ($, e, next) => {
    const composed = await next(e)
    if (e.traits.includes('bare') || !(await canDraw($, e.surfaces))) return composed
    return { sections: [...composed.sections, MERMAID_HINT] }
  })

  on('command.run', { command: 'md' }, async ($, e) => {
    const arg = e.args.trim()
    const current = await read($, view)
    if (!arg && !current.path) return { text: '表示する .md がありません。/md <path> で指定してください。' }
    await open($)
    await load($, arg ? await absolute($, arg) : undefined)
    const { path } = await read($, view)
    return { text: `Markdown ペインで表示: ${path}` }
  })

  on('tool.call', { tool: 'Write' }, async ($, e, next) => {
    const ran = await next(e)
    await follow($, e.file_path)
    return ran
  })
  on('tool.call', { tool: 'Edit' }, async ($, e, next) => {
    const ran = await next(e)
    await follow($, e.file_path)
    return ran
  })

  // 端末の返答中の mermaid を図に描き直す(保存される本文は元のまま、ctrl+o で原文)
  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    const text = e.props.text
    if (e.surface !== 'terminal' || !/^(`{3,}|~{3,})mermaid/m.test(text)) return next(e)
    const segments = split(text)
    if (!segments.some(s => s.kind === 'mermaid')) return next(e)
    await hintInstall($)
    const cols = Math.max(20, (e.viewport?.columns ?? 80) - 4)
    let out = ''
    for (const s of segments) {
      if (s.kind !== 'mermaid') out += s.text
      else {
        const ascii = await toAscii($, s.text, cols)
        out += ascii ? '```text\n' + ascii + '\n```' : '```mermaid\n' + s.text + '```'
      }
    }
    return next({ ...e, props: { ...e.props, text: out } })
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    lastCols = e.props.bodyColumns
    const v = await read($, view)
    const toggleMode = () =>
      update($, view, (x): MdView => ({ ...x, mode: x.mode === 'builtin' ? 'leaf' : 'builtin' })).then(() => load($))
    const toggleFollow = () => update($, view, x => ({ ...x, follow: !x.follow }))

    return (
      <Box flexDirection="column">
        <Text dimColor wrap="truncate-start">{v.path ?? '(未選択: /md <path>)'}</Text>
        <Box flexDirection="row" gap={1}>
          <Button key="mode" hotkey="l" onPress={toggleMode}>
            {v.mode === 'builtin' ? '組込み+mermaid' : 'leaf 全面'}
          </Button>
          <Button key="follow" hotkey="f" onPress={toggleFollow}>
            {v.follow ? '追従 ON' : '追従 OFF'}
          </Button>
          <Button key="reload" hotkey="r" onPress={() => load($)}>再読込</Button>
        </Box>
        {v.note && <Text color="warning">{v.note}</Text>}
        {await drawSegments($, e, v.segments, lastCols)}
      </Box>
    )
  })
}
