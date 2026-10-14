import { describe, expect, it } from 'vitest'
import {
  STREAK_COPY, STREAK_TONES, toneFor, indexFor, fill, streakNotification, totalLines,
} from './streak-copy.js'

const all = () => Object.values(STREAK_COPY).flatMap(s => s.lines)

describe('streak copy', () => {
  it('carries at least a hundred distinct lines', () => {
    expect(totalLines()).toBeGreaterThanOrEqual(100)
    expect(new Set(all()).size).toBe(totalLines())   // nothing repeated across sets
  })

  it('has a title and lines for every tone', () => {
    for (const tone of STREAK_TONES) {
      expect(STREAK_COPY[tone], tone).toBeTruthy()
      expect(STREAK_COPY[tone].title.length, tone).toBeGreaterThan(0)
      expect(STREAK_COPY[tone].lines.length, tone).toBeGreaterThanOrEqual(20)
    }
  })

  // A notification body is truncated hard on a locked screen. {0} is the routine name, which can
  // be long, so the template itself has to leave room for it.
  it('keeps every line short enough for a locked screen', () => {
    for (const line of all()) expect(line.length, line).toBeLessThanOrEqual(70)
  })

  it('never leaves an unexpanded token in the finished body', () => {
    for (const line of all()) {
      expect(line.replace('{0}', 'Push'), line).not.toContain('{0}')
    }
    expect(fill('{0} is on when you’re ready.', 'Legs')).toBe('Legs is on when you’re ready.')
    expect(fill('{0} is on when you’re ready.', '')).toBe('the session is on when you’re ready.')
  })

  it('rotates by date, so a day keeps its line and consecutive days differ', () => {
    const n = STREAK_COPY.friendly.lines.length
    expect(indexFor('2026-09-07', n)).toBe(indexFor('2026-09-07', n))     // same day, same line
    const a = streakNotification('2026-09-07', 'friendly', 'Push')
    const b = streakNotification('2026-09-08', 'friendly', 'Push')
    expect(a.body).not.toBe(b.body)
  })

  it('falls back to friendly for a tone it does not know', () => {
    expect(toneFor('drill')).toBe('drill')
    expect(toneFor('celebrate')).toBe('celebrate')
    expect(toneFor('nope')).toBe('friendly')
    expect(toneFor(undefined)).toBe('friendly')
    expect(streakNotification('2026-09-07', 'nope', 'Push').title)
      .toBe(STREAK_COPY.friendly.title)
  })

  it('answers with a title and a body naming the routine', () => {
    const n = streakNotification('2026-09-07', 'guilt', 'Pull')
    expect(n.title).toBe(STREAK_COPY.guilt.title)
    expect(n.body).toContain('Pull')
    expect(n.tone).toBe('guilt')
  })

  // The four registers Stan asked for: warm, tender/possessive, and straight-talking.
  it('keeps the three registers apart', () => {
    const pick = t => streakNotification('2026-09-07', t, 'Push').body
    expect(pick('celebrate')).not.toBe(pick('friendly'))
    expect(pick('friendly')).not.toBe(pick('guilt'))
    expect(pick('guilt')).not.toBe(pick('drill'))
    // A missed day is never reassuring, whatever the tone.
    for (const line of STREAK_COPY.guilt.lines) expect(line).not.toMatch(/well done|great job|nice work/i)
  })
})