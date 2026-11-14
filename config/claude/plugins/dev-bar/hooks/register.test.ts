import { expect, test } from 'claude-code/testing'

import { prettyModel } from './register'

test('prettyModel turns Claude model ids into display names', () => {
  expect(prettyModel('claude-opus-5-5')).toBe('Opus 5.5')
  expect(prettyModel('claude-sonnet-5-5[1m]')).toBe('Sonnet 5.5 (1M)')
  expect(prettyModel('claude-haiku-4-5-20251001')).toBe('Haiku 4.5')
  expect(prettyModel('claude-fable-5')).toBe('Fable 5')
  expect(prettyModel('opus')).toBe('opus')
})
