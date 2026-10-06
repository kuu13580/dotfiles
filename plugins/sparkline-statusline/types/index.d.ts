export type RateLimit = { kind: string; percentUsed: number; resetsAt?: string }

export type Usage = { ctxPercent?: number; rateLimits: RateLimit[] }

export type CacheStats = {
  inputTokens: number
  readTokens: number
  creationTokens: number
  lastResponseAt: number | null
  lastHadCache: boolean
  ttl: '5m' | '1h' | null
}

declare module 'claude-code' {
  interface PluginState {
    'sparkline-statusline': { usage: Usage; cache: CacheStats }
  }
}
