import { expect, test } from 'claude-code/testing'

import { formatTokens, prettyModel } from './register'

test('prettyModel turns Claude model ids into display names', () => {
  expect(prettyModel('claude-opus-5-5')).toBe('Opus 5.5')
  expect(prettyModel('claude-sonnet-5-5[1m]')).toBe('Sonnet 5.5 (1M)')
  expect(prettyModel('claude-haiku-4-5-20251001')).toBe('Haiku 4.5')
  expect(prettyModel('claude-fable-5')).toBe('Fable 5')
  expect(prettyModel('opus')).toBe('opus')
})

test('formatTokens shortens token counts', () => {
  expect(formatTokens(45_210)).toBe('45k')
  expect(formatTokens(200_000)).toBe('200k')
  expect(formatTokens(999_499)).toBe('999k')
  expect(formatTokens(999_500)).toBe('1M')
  expect(formatTokens(1_000_000)).toBe('1M')
  expect(formatTokens(1_250_000)).toBe('1.3M')
})
