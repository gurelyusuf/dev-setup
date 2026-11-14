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

const usageColor = (percent: number) => (percent >= 80 ? 'error' : percent >= 50 ? 'warning' : 'success')

const refresh = async ($: EngineInterface) => {
  const model = await $.session.model()
  const { percent } = (await $.session.usage()).context
  // Outside a repo git exits non-zero; on a detached HEAD it prints nothing. Both show no branch.
  const git = await $.process.run(['git', 'branch', '--show-current'])
  const branch = git.exitCode === 0 ? git.stdout.trim() || null : null
  const next: Status = { model, percent: percent ?? null, branch }
  await update($, status, () => next)
}

// Plugin skills run by their namespaced names, as ponytail's own band runs them.
const run = ($: EngineInterface, command: string) =>
  $.command
    .run({ command, args: '' })
    .catch(() => $.ui.toast(`/${command} could not run: is its plugin enabled?`))

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

    return (
      <Box flexDirection="row" alignItems="center" gap={2} width={width}>
        {s && <Text color="claude">{prettyModel(s.model)}</Text>}
        {s && s.percent !== null && <Text color={usageColor(s.percent)}>{s.percent}%</Text>}
        <Box flexGrow={1} />
        <Button key="review" plain onPress={() => run($, 'ponytail:ponytail-review')}>
          <Text color="success">Review</Text>
        </Button>
        <Button key="audit" plain onPress={() => run($, 'ponytail:ponytail-audit')}>
          <Text color="warning">Audit</Text>
        </Button>
        <Button key="commit" plain onPress={() => run($, 'caveman:caveman-commit')}>
          <Text color="suggestion">Commit</Text>
        </Button>
        {s?.branch && <Text color="remember">{s.branch}</Text>}
      </Box>
    )
  })
}
