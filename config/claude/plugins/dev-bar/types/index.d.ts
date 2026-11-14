export type Status = { model: string; percent: number | null; branch: string | null }

declare module 'claude-code' {
  interface PluginState {
    'dev-bar': { status: Status | null }
  }
}
