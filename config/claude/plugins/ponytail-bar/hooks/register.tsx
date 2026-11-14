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

    return (
      <Box flexDirection="row" alignItems="center" gap={2}>
        {s && <Text dimColor>{s.percent === null ? s.model : `${s.model} · ctx ${s.percent}%`}</Text>}
        <Button key="review" plain label="Review" onPress={() => run($, 'ponytail:ponytail-review')} />
        <Button key="audit" plain label="Audit" onPress={() => run($, 'ponytail:ponytail-audit')} />
      </Box>
    )
  })
}
