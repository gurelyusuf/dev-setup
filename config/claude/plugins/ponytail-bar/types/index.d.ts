export type Status = { model: string; percent: number | null }

declare module 'claude-code' {
  interface PluginState {
    'ponytail-bar': { status: Status | null }
  }
}
