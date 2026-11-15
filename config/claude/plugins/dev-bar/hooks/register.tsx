import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Status } from '../types'

const status = atom({ plugin: 'dev-bar', key: 'status' } as const, null)

// `claude-opus-5-5[1m]` -> `Opus 5.5 (1M)`; anything else (an alias, another provider's id) as given.
export const prettyModel = (id: string) => {
  const m = /^claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?(\[1m\])?$/.exec(id)
  if (!m) {
    return id
  }
  const [, family = '', major, minor, long] = m
  return `${family.charAt(0).toUpperCase()}${family.slice(1)} ${major}${minor ? `.${minor}` : ''}${long ? ' (1M)' : ''}`
}

// 45210 -> `45k`, 1000000 -> `1M`, 1250000 -> `1.3M`.
export const formatTokens = (n: number) =>
  n >= 1_000_000 ? `${+(n / 1_000_000).toFixed(1)}M` : `${Math.round(n / 1000)}k`

const usageColor = (percent: number) => (percent >= 80 ? 'error' : percent >= 50 ? 'warning' : 'success')

const refresh = async ($: EngineInterface) => {
  const model = await $.session.model()
  const { tokens, window, percent } = (await $.session.usage()).context
  // Outside a repo git exits non-zero; on a detached HEAD it prints nothing. Both show no branch.
  const git = await $.process.run(['git', 'branch', '--show-current'])
  const branch = git.exitCode === 0 ? git.stdout.trim() || null : null
  const next: Status = { model, tokens: tokens ?? null, window, percent: percent ?? null, branch }
  await update($, status, () => next)
}

// Plugin skills run by their namespaced names, as ponytail's own band runs them.
const run = ($: EngineInterface, command: string) =>
  $.command
    .run({ command, args: '' })
    .catch(() => $.ui.toast(`/${command} could not run: is its plugin enabled?`))

const CHECK_PROMPT =
  "Run this repository's lint, typecheck and test scripts and report each result."

const check = ($: EngineInterface) =>
  $.prompt.submit({ text: CHECK_PROMPT }).catch(() => $.ui.toast('Check could not be sent'))

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    await refresh($)
    return result
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    await refresh($)
    return result
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) {
      return next(e)
    }

    const s = await read($, status)
    const { Box, Button, Text } = $.ui.resolve(e)
    // As in ponytail's band: bodyColumns counts terminal cells, so other surfaces size the row themselves.
    const width = e.surface === 'terminal' ? e.props.bodyColumns : undefined

    const hasContext = s !== null && s.tokens != null && s.percent !== null
    const dot = <Text dimColor>·</Text>

    return (
      <Box flexDirection="row" alignItems="center" gap={1} width={width}>
        {s && <Text color="claude">{prettyModel(s.model)}</Text>}
        {hasContext && dot}
        {hasContext && (
          <Text color={usageColor(s.percent!)}>
            {formatTokens(s.tokens!)} / {formatTokens(s.window)}
          </Text>
        )}
        <Box flexGrow={1} />
        <Button key="check" plain onPress={() => check($)}>
          <Text color="suggestion">Check</Text>
        </Button>
        {dot}
        <Button key="review" plain onPress={() => run($, 'ponytail:ponytail-review')}>
          <Text color="success">Review</Text>
        </Button>
        {dot}
        <Button key="audit" plain onPress={() => run($, 'ponytail:ponytail-audit')}>
          <Text color="warning">Audit</Text>
        </Button>
        {dot}
        <Button key="security" plain onPress={() => run($, 'security-audit')}>
          <Text color="error">Security</Text>
        </Button>
        {s?.branch && dot}
        {s?.branch && <Text color="merged">{s.branch}</Text>}
      </Box>
    )
  })
}
