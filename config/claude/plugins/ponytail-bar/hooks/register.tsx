import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Status } from '../types'

const status = atom({ plugin: 'ponytail-bar', key: 'status' } as const, null)

const refresh = async ($: EngineInterface) => {
  const model = await $.session.model()
  const { percent } = (await $.session.usage()).context
  const next: Status = { model, percent: percent ?? null }
  await update($, status, () => next)
}

// Same command names ponytail's own band runs.
const run = ($: EngineInterface, command: string) =>
  $.command
    .run({ command, args: '' })
    .catch(() => $.ui.toast(`/${command} could not run: is the ponytail plugin enabled?`))

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
        {s && <Text dimColor>{s.percent === null ? s.model : `${s.model} · ctx ${s.percent}%`}</Text>}
        <Box flexGrow={1} />
        <Button key="review" plain onPress={() => run($, 'ponytail:ponytail-review')}>
          <Text color="success">✓ Review</Text>
        </Button>
        <Button key="audit" plain onPress={() => run($, 'ponytail:ponytail-audit')}>
          <Text color="warning">⚠ Audit</Text>
        </Button>
      </Box>
    )
  })
}
