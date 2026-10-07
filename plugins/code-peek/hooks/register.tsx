import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Candidate, Pos, Ref, View } from '../types'

const PANE = 'code-peek'
const HEADER_ROWS = 1
const MAX_CANDIDATES = 20
const view = atom({ plugin: 'code-peek', key: 'view' } as const, null as View | null)
const pos = atom({ plugin: 'code-peek', key: 'pos' } as const, { top: 0 } as Pos)

// `path:10-20` or GitHub's `path#L10-L20`
const REF_SOURCE = String.raw`(\/?(?:[\w.@~-]+\/)*[\w.@-]*\.[A-Za-z]\w{0,9})(?::(\d+)(?:-(\d+))?|#L(\d+)(?:-L(\d+))?)`
const REF = new RegExp(`^${REF_SOURCE}$`)
// Markdown links, URLs and inline code are matched first so a ref inside them is left alone.
const TOKEN = new RegExp(String.raw`(\[[^\]\n]*\]\([^)\n]*\))|(https?:\/\/\S+)|(\x60[^\x60\n]+\x60)|` + REF_SOURCE, 'g')

const refOf = (m: RegExpExecArray): Ref => {
  const line = Number(m[2] ?? m[4])
  const endLine = Number(m[3] ?? m[5])
  return { path: m[1]!, line, ...(endLine > line ? { endLine } : {}) }
}

const toHref = (ref: Ref) => `file:${ref.path}#L${ref.line}${ref.endLine ? `-L${ref.endLine}` : ''}`

export const parseHref = (href: string): Ref | undefined => {
  const m = /^file:(.+?)#L(\d+)(?:-L(\d+))?$/.exec(href)
  if (!m) return undefined
  const line = Number(m[2])
  const endLine = m[3] ? Number(m[3]) : undefined
  return { path: m[1]!, line, ...(endLine && endLine > line ? { endLine } : {}) }
}

type Linked = { text: string; hrefs: string[] }
// Every redraw of the transcript re-renders each message, while a finished message's text never changes.
const linked = new Map<string, Linked>()

export const linkify = (text: string): Linked => {
  const hit = linked.get(text)
  if (hit) return hit
  const hrefs = new Set<string>()
  const linkifySegment = (segment: string) =>
    segment.replace(TOKEN, (whole: string, mdLink?: string, url?: string, code?: string) => {
      if (mdLink || url) return whole
      const m = REF.exec(code ? code.slice(1, -1) : whole)
      if (!m) return whole
      const href = toHref(refOf(m))
      hrefs.add(href)
      return `[${whole}](${href})`
    })
  const out = text
    .split(/(^```[\s\S]*?^```)/m)
    .map((part, i) => (i % 2 === 1 ? part : linkifySegment(part)))
    .join('')
  const result = { text: out, hrefs: [...hrefs] }
  if (linked.size >= 200) linked.delete(linked.keys().next().value!)
  linked.set(text, result)
  return result
}

// Changed files come first, then candidates whose length can hold the line.
export const rankCandidates = (candidates: string[], changed: Set<string>, lineCounts: Map<string, number>, line: number) => {
  const fits = candidates.filter(c => (lineCounts.get(c) ?? Infinity) >= line)
  const pool = fits.length > 0 ? fits : candidates
  const touched = pool.filter(c => changed.has(c))
  return touched.length > 0 ? touched : pool
}

const git = async ($: EngineInterface, argv: string[], cwd?: string) => {
  const r = await $.process.run(['git', ...argv], cwd ? { cwd } : undefined)
  return r.exitCode === 0 ? r.stdout : undefined
}

const changedFiles = async ($: EngineInterface, top: string) => {
  const bases = await Promise.all(['origin/HEAD', 'origin/main', 'origin/master'].map(ref => git($, ['merge-base', 'HEAD', ref], top)))
  const base = bases.find(Boolean)?.trim()
  const [committed, working] = await Promise.all([
    base ? git($, ['diff', '--name-only', `${base}...HEAD`], top) : '',
    git($, ['diff', '--name-only', 'HEAD'], top),
  ])
  return new Set(`${committed ?? ''}\n${working ?? ''}`.split('\n').filter(Boolean))
}

const countLines = async ($: EngineInterface, path: string) => {
  try {
    return (await $.fs.read(path)).split('\n').length
  } catch {
    return 0
  }
}

const resolve = async ($: EngineInterface, ref: Ref): Promise<Candidate[]> => {
  if (await $.fs.exists(ref.path)) return [{ file: ref.path, display: ref.path }]
  const top = (await git($, ['rev-parse', '--show-toplevel']))?.trim()
  if (!top) return []
  const want = ref.path.replace(/^\.?\//, '')
  // A pathspec keeps the output small; listing every file overflows the 4 MiB stdout cap in large repos.
  const listed = await git($, ['ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', want, `:(glob)**/${want}`], top)
  const matches = [...new Set((listed ?? '').split('\0').filter(Boolean))].slice(0, MAX_CANDIDATES)
  const toCandidate = (f: string): Candidate => ({ file: `${top}/${f}`, display: f })
  if (matches.length <= 1) return matches.map(toCandidate)
  const [changed, counts] = await Promise.all([
    changedFiles($, top),
    Promise.all(matches.map(f => countLines($, `${top}/${f}`))),
  ])
  const lineCounts = new Map(matches.map((f, i) => [f, counts[i]!]))
  return rankCandidates(matches, changed, lineCounts, ref.line).map(toCandidate)
}

const setView = ($: EngineInterface, v: View) => update($, view, () => v)

// Only the path goes into $.state: the pane reads state on every scroll tick, so the lines stay here.
let cached: { file: string; lines: string[] } | undefined

const linesOf = async ($: EngineInterface, file: string) => {
  if (cached?.file !== file) cached = { file, lines: (await $.fs.read(file)).split('\n') }
  return cached.lines
}

const show = async ($: EngineInterface, c: Candidate, ref: Ref) => {
  let lines: string[]
  try {
    cached = undefined
    lines = await linesOf($, c.file)
  } catch (err) {
    await setView($, { kind: 'error', message: `${c.display} を読めませんでした: ${String(err)}` })
    return
  }
  if (ref.line > lines.length) {
    await setView($, { kind: 'error', message: `${c.display} は ${lines.length} 行しかありません (指定: ${ref.line} 行目)` })
    return
  }
  const endLine = Math.min(ref.endLine ?? ref.line, lines.length)
  await update($, pos, (): Pos => ({ center: Math.floor((ref.line + endLine) / 2) }))
  await setView($, { kind: 'code', ...c, line: ref.line, endLine, total: lines.length })
}

export const topOf = (p: Pos, total: number, rows: number) => {
  const top = 'top' in p ? p.top : p.center - 1 - Math.floor(rows / 2)
  return Math.max(0, Math.min(top, total - rows))
}

export const peek = async ($: EngineInterface, ref: Ref) => {
  const found = await resolve($, ref)
  if (found.length === 1) await show($, found[0]!, ref)
  else if (found.length === 0) await setView($, { kind: 'error', message: `${ref.path} に一致するファイルが見つかりません` })
  else await setView($, { kind: 'choose', ref, candidates: found })
  await $.ui.open({ id: PANE, title: `${ref.path}:${ref.line}` })
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'peek',
      description: 'path:line のファイルを pane に表示し、その行までスクロールする',
      argumentHint: '<path>:<line>[-<end>] | <path>#L<line>[-L<end>]',
    })
    return next(e)
  })

  on('command.run', { command: 'peek' }, async ($, e) => {
    const m = REF.exec(e.args.trim().replace(/^\x60|\x60$/g, ''))
    if (!m) return { text: `使い方: /peek <path>:<line>[-<end>] または <path>#L<line>[-L<end>]` }
    await peek($, refOf(m))
    return {}
  })

  // Clicks only reach plugins in the fullscreen terminal; elsewhere the engine's own rendering is kept.
  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    if (e.surface !== 'terminal' || !e.viewport?.isFullscreen) return next(e)
    const linked = linkify(e.props.text)
    if (linked.hrefs.length === 0) return next(e)
    const { Markdown } = $.ui.resolve(e)
    return (
      <Markdown
        key="code-peek-refs"
        text={linked.text}
        pressableLinks={linked.hrefs.slice(0, 256)}
        onLinkPress={link => {
          const ref = parseHref(link.href)
          if (ref) void peek($, ref)
        }}
      />
    )
  })

  // Scrolled here instead of by the engine so the header row never leaves the pane.
  on('ui.scroll', { requestId: PANE }, async ($, e, next) => {
    const v = await read($, view)
    if (v?.kind !== 'code') return next(e)
    const total = v.total
    const rows = Math.max(1, e.bodyRows - HEADER_ROWS)
    await update($, pos, (p): Pos => ({ top: topOf({ top: topOf(p, total, rows) + e.by }, total, rows) }))
    return {}
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Code, Button } = $.ui.resolve(e)
    const v = await read($, view)
    if (!v) return <Text dimColor>path:line をクリックすると、ここに前後の行を表示します</Text>
    if (v.kind === 'error') return <Text color="red">{v.message}</Text>
    if (v.kind === 'choose') {
      return (
        <Box flexDirection="column">
          <Text>{`${v.ref.path}:${v.ref.line} に一致するファイルが複数あります`}</Text>
          {v.candidates.map((c, i) => (
            <Button key={`pick-${i}`} plain onPress={() => void show($, c, v.ref)}>
              {c.display}
            </Button>
          ))}
        </Box>
      )
    }
    let lines: string[]
    try {
      lines = await linesOf($, v.file)
    } catch (err) {
      return <Text color="red">{`${v.display} を読めませんでした: ${String(err)}`}</Text>
    }
    const rows = Math.max(1, e.props.scroll.bodyRows - HEADER_ROWS)
    const top = topOf(await read($, pos), lines.length, rows)
    const shown = lines.slice(top, top + rows)
    const lo = Math.max(0, Math.min(v.line - 1 - top, shown.length))
    const hi = Math.max(lo, Math.min(v.endLine - top, shown.length))
    // Drawn here rather than by Code so the width stays at the file's digit count while scrolling.
    const digits = String(lines.length).length
    const gutter = (from: number, to: number, mark: string) =>
      shown.slice(from, to).map((_, i) => `${mark} ${String(top + from + i + 1).padStart(digits)}`).join('\n')
    const at = v.endLine > v.line ? `${v.line}-${v.endLine}` : `${v.line}`
    const header = ` ${v.display}:${at}  (${top + 1}-${top + shown.length} / ${lines.length})`
    return (
      <Box flexDirection="column">
        <Text inverse bold wrap="truncate-end">{header.padEnd(e.props.bodyColumns)}</Text>
        <Box flexDirection="row">
          <Box flexDirection="column" width={digits + 3} minWidth={digits + 3} flexShrink={0}>
            {lo > 0 && <Text dimColor>{gutter(0, lo, ' ')}</Text>}
            {hi > lo && <Text color="yellow" bold>{gutter(lo, hi, '▌')}</Text>}
            {hi < shown.length && <Text dimColor>{gutter(hi, shown.length, ' ')}</Text>}
          </Box>
          {/* Code trims blank lines at the edges of its source, which would push its rows out of line with the gutter. */}
          <Code source={shown.map(l => (l.trim() === '' ? '\u00a0' : l)).join('\n')} path={v.display} wrap="truncate-end" />
        </Box>
      </Box>
    )
  })
}
