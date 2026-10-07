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
    'code-peek': { view: View | null; pos: Pos }
  }
}
