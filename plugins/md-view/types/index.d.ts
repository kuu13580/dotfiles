export type MdSegment = { kind: 'md' | 'pre' | 'mermaid'; text: string }

// `leaf` renders the whole file with `leaf --inline` instead of the built-in Markdown.
export type MdMode = 'builtin' | 'leaf'

export type MdView = {
  path?: string
  mode: MdMode
  follow: boolean
  segments: MdSegment[]
  note?: string
}

declare module 'claude-code' {
  interface PluginState {
    'md-view': { view: Shaped<MdView> }
  }
}
