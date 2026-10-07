import type { EngineInterface, Register } from 'claude-code'

export const EDITORS = ['code', 'zed'] as const
type Editor = (typeof EDITORS)[number]
const LAST = 'lastEditor'

const isEditor = (s: string): s is Editor => (EDITORS as readonly string[]).includes(s)

// Worktree root rather than cwd so a session sitting in a subdirectory still opens the whole tree.
const targetDir = async ($: EngineInterface) => {
  const cwd = await $.session.cwd()
  const r = await $.process.run(['git', 'rev-parse', '--show-toplevel'], { cwd })
  return r.exitCode === 0 && r.stdout.trim() ? r.stdout.trim() : cwd
}

export const open = async ($: EngineInterface, args: string) => {
  const arg = args.trim()
  if (arg && !isEditor(arg)) return { text: `使い方: /open [${EDITORS.join('|')}]` }
  const last = await $.store.get(LAST)
  const editor: Editor = arg ? (arg as Editor) : typeof last === 'string' && isEditor(last) ? last : 'code'
  const dir = await targetDir($)
  try {
    const r = await $.process.run([editor, dir], { timeoutMs: 20_000 })
    if (r.exitCode !== 0) return { text: `${editor} の起動に失敗しました (exit ${r.exitCode}): ${r.stderr.trim()}` }
  } catch (err) {
    return { text: `${editor} を起動できません: ${err instanceof Error ? err.message : String(err)}` }
  }
  await $.store.set(LAST, editor)
  $.ui.toast(`${editor} で ${dir} を開きました`)
  return {}
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'open',
      description: 'セッションの worktree を code / zed で開く (省略時は前回のエディタ)',
      argumentHint: EDITORS.join('|'),
      immediate: true,
    })
    return next(e)
  })

  on('command.run', { command: 'open' }, async ($, e) => open($, e.args))
}
