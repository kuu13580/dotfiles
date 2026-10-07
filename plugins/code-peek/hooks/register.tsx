import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Candidate, Pos, Ref, View } from '../types'

const PANE = 'code-peek'
const HEADER_ROWS = 1
const MAX_CANDIDATES = 20
const RECENT_TURNS = 3
const RECENT_REFS = 20
const view = atom({ plugin: 'code-peek', key: 'view' } as const, null as View | null)
const pos = atom({ plugin: 'code-peek', key: 'pos' } as const, { top: 0 } as Pos)
const recent = atom({ plugin: 'code-peek', key: 'recent' } as const, [] as Ref[][])

// `path:10-20` or GitHub's `path#L10-L20`
const REF_SOURCE = String.raw`(\/?(?:[\w.@~-]+\/)*[\w.@-]*\.[A-Za-z]\w{0,9})(?::(\d+)(?:-(\d+))?|#L(\d+)(?:-L(\d+))?)`
const REF = new RegExp(`^${REF_SOURCE}$`)
// Without a line, a path needs a directory, or a file name needs a listed extension:
// `JSON.parse` and `console.log` read like file names, so the extension is what tells them apart.
const PATH_SOURCE = String.raw`\/?(?:[\w.@~-]+\/)+[\w.@-]*\.[A-Za-z]\w{0,9}`
const FILE_EXTS = 'ts|tsx|js|jsx|mjs|cjs|json|md|yml|yaml|toml|py|sh|css|scss|html|vue|go|rs|java|kt|rb|php|sql'
const FILE_SOURCE = String.raw`[\w@-][\w.@-]*\.(?:${FILE_EXTS})(?!\w|\.\w)`
const PATH_ONLY = new RegExp(`^(?:${PATH_SOURCE}|${FILE_SOURCE})$`)
// Markdown links, URLs and inline code are matched first so a ref inside them is left alone.
// A ref may only start at a token boundary, so a long token without one is not rescanned from every character.
const TOKEN = new RegExp(
  String.raw`(\[[^\]\n]*\]\([^)\n]*\))|(https?:\/\/\S+)|(\x60[^\x60\n]+\x60)|` +
    String.raw`(?<![\w.@~/-])(?:${REF_SOURCE}|${PATH_SOURCE}|${FILE_SOURCE})`,
  'g',
)

const refOf = (m: RegExpExecArray): Ref => {
  const line = Number(m[2] ?? m[4])
  const endLine = Number(m[3] ?? m[5])
  return { path: m[1]!, line, ...(endLine > line ? { endLine } : {}) }
}

const refFrom = (s: string): Ref | undefined => {
  const m = REF.exec(s)
  return m ? refOf(m) : PATH_ONLY.test(s) ? { path: s, line: 0 } : undefined
}

const toHref = (ref: Ref) =>
  `file:${ref.path}${ref.line ? `#L${ref.line}` : ''}${ref.endLine ? `-L${ref.endLine}` : ''}`

export const parseHref = (href: string): Ref | undefined => {
  const m = /^file:(.+?)(?:#L(\d+)(?:-L(\d+))?)?$/.exec(href)
  if (!m) return undefined
  // A pressed link comes back as the surface resolved it (`file:///abs/path`, percent-encoded), not as written.
  let path = m[1]!.replace(/^\/\/[^/]*/, '')
  try {
    path = decodeURIComponent(path)
  } catch {}
  const line = Number(m[2] ?? 0)
  const endLine = m[3] ? Number(m[3]) : undefined
  return { path, line, ...(endLine && endLine > line ? { endLine } : {}) }
}

type Linked = { text: string; hrefs: string[]; refs: Ref[] }
// Every redraw of the transcript re-renders each message, while a finished message's text never changes.
const linked = new Map<string, Linked>()

export const linkify = (text: string): Linked => {
  const hit = linked.get(text)
  if (hit) return hit
  const refs = new Map<string, Ref>()
  const linkifySegment = (segment: string) =>
    segment.replace(TOKEN, (whole: string, mdLink?: string, url?: string, code?: string) => {
      if (mdLink || url) return whole
      const ref = refFrom(code ? code.slice(1, -1) : whole)
      if (!ref) return whole
      const href = toHref(ref)
      refs.set(href, ref)
      return `[${whole}](${href})`
    })
  const out = text
    .split(/(^```[\s\S]*?^```)/m)
    .map((part, i) => (i % 2 === 1 ? part : linkifySegment(part)))
    .join('')
  const result = { text: out, hrefs: [...refs.keys()], refs: [...refs.values()] }
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

// The session's directory never changes, so neither does its repository root.
let repoRoot: Promise<string | undefined> | undefined

const rootOf = ($: EngineInterface) => (repoRoot ??= git($, ['rev-parse', '--show-toplevel']).then(s => s?.trim()))

const under = (dir: string | undefined, path: string) => (dir && path.startsWith(`${dir}/`) ? path.slice(dir.length + 1) : path)

const resolve = async ($: EngineInterface, ref: Ref): Promise<Candidate[]> => {
  const [top, exists] = await Promise.all([rootOf($), $.fs.exists(ref.path)])
  if (exists) return [{ file: ref.path, display: under(top, ref.path) }]
  if (!top) return []
  // A pressed link comes back resolved against the session directory (`/cwd/api.ts`), so search by what was written.
  const want = under(await $.session.cwd(), ref.path).replace(/^\.?\//, '')
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
  await update($, pos, (): Pos => (ref.line ? { center: Math.floor((ref.line + endLine) / 2) } : { top: 0 }))
  await setView($, { kind: 'code', ...c, line: ref.line, endLine, total: lines.length })
}

const refKey = (r: Ref) => (r.line ? `${r.path}:${r.line}${r.endLine ? `-${r.endLine}` : ''}` : r.path)

// Newest reply first; a ref already listed under a newer reply is dropped from the older ones.
export const addRecent = (groups: Ref[][], refs: Ref[]): Ref[][] => {
  const seen = new Set<string>()
  let room = RECENT_REFS
  return [refs, ...groups].slice(0, RECENT_TURNS).flatMap(g => {
    const kept = g
      .filter(r => {
        const key = refKey(r)
        return !seen.has(key) && !!seen.add(key)
      })
      .slice(0, room)
    room -= kept.length
    return kept.length > 0 ? [kept] : []
  })
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
  await $.ui.open({ id: PANE, title: refKey(found.length === 1 ? { ...ref, path: found[0]!.display } : ref) })
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'peek',
      description: '直近の返答の参照一覧、または path:line のファイルを pane に表示する',
      argumentHint: '[<path>:<line>[-<end>] | <path>#L<line>[-L<end>]]',
    })
    return next(e)
  })

  on('command.run', { command: 'peek' }, async ($, e) => {
    const arg = e.args.trim().replace(/^\x60|\x60$/g, '')
    if (arg === '') {
      await update($, view, () => null)
      await $.ui.open({ id: PANE, title: 'code-peek' })
      return {}
    }
    const ref = refFrom(arg)
    if (!ref) return { text: `使い方: /peek (直近の参照一覧) | /peek <path>[:<line>[-<end>]] | /peek <path>#L<line>[-L<end>]` }
    await peek($, ref)
    return {}
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined && e.reason === 'answer') {
      const { refs } = linkify(e.answer)
      if (refs.length > 0) await update($, recent, groups => addRecent(groups, refs))
    }
    return result
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
    if (!v) {
      const groups = await read($, recent)
      if (groups.length === 0) return <Text dimColor>直近の返答に path:line の参照はまだありません</Text>
      return (
        <Box flexDirection="column">
          {groups.map((g, gi) => (
            <Box key={`group-${gi}`} flexDirection="column" marginBottom={1}>
              <Text dimColor>{`${gi === 0 ? '直近の返答' : `${gi} つ前の返答`} (${g.length})`}</Text>
              {g.map((r, i) => (
                <Button key={`ref-${gi}-${i}`} plain onPress={() => void peek($, r)}>
                  {refKey(r)}
                </Button>
              ))}
            </Box>
          ))}
        </Box>
      )
    }
    const back = (
      <Button key="back" plain onPress={() => void update($, view, () => null)}>
        ← 一覧
      </Button>
    )
    if (v.kind !== 'code') {
      return (
        <Box flexDirection="column">
          {back}
          {v.kind === 'error' ? (
            <Text color="red">{v.message}</Text>
          ) : (
            <>
              <Text>{`${refKey(v.ref)} に一致するファイルが複数あります`}</Text>
              {v.candidates.map((c, i) => (
                <Button key={`pick-${i}`} plain onPress={() => void show($, c, v.ref)}>
                  {c.display}
                </Button>
              ))}
            </>
          )}
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
    const at = v.endLine > v.line ? `:${v.line}-${v.endLine}` : v.line ? `:${v.line}` : ''
    const header = ` ${v.display}${at}  (${top + 1}-${top + shown.length} / ${lines.length})`
    return (
      <Box flexDirection="column">
        <Box flexDirection="row">
          {back}
          <Text inverse bold wrap="truncate-end">{header.padEnd(e.props.bodyColumns)}</Text>
        </Box>
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
