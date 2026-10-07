// `line` 0 means the whole file, opened from the top with no line marked.
export type Ref = { path: string; line: number; endLine?: number }

// `file` is what $.fs reads, `display` the repo-relative path shown in the pane.
export type Candidate = { file: string; display: string }

export type View =
  | ({ kind: 'code'; line: number; endLine: number; total: number } & Candidate)
  | { kind: 'choose'; ref: Ref; candidates: Candidate[] }
  | { kind: 'error'; message: string }

// The pane scrolls itself so the header stays put; `center` holds until the first scroll knows the body height.
export type Pos = { center: number } | { top: number }

declare module 'claude-code' {
  interface PluginState {
    // `recent` holds the refs of the latest replies, newest first.
    'code-peek': { view: View | null; pos: Pos; recent: Ref[][] }
  }
}
