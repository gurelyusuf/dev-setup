export type Status = { model: string; percent: number | null }

declare module 'claude-code' {
  interface PluginState {
    'dev-bar': { status: Status | null }
  }
}
