import { describe, expect, it } from 'vitest'
import {
  STREAK_COPY, STREAK_TONES, toneFor, indexFor, fill, streakNotification, totalLines,
  STREAK_MILESTONES, milestoneNotification,
} from './streak-copy.js'
import { buildMilestoneNotification } from './mobile.js'

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
// The scheduling side of milestones lives in mobile.js; the words live here. Both are tested
// together because the interesting cases are both: which milestones say something, and which of
// them are allowed to fire.
describe('milestone notifications', () => {
  const now = new Date(2026, 8, 7, 18, 0)               // Monday evening
  const S = w => ({ workouts: w.map(d => ({ d })) })

  it('says something for every milestone and nothing for the gaps', () => {
    for (const w of STREAK_MILESTONES) {
      expect(milestoneNotification(w), `week ${w}`).toBeTruthy()
      expect(milestoneNotification(w).body.length, `week ${w}`).toBeLessThanOrEqual(70)
    }
    for (const w of [0, 5, 7, 9, 11, 13, 14, 15, 17, 19, 50, 51, 103, 105, 200]) {
      expect(milestoneNotification(w), `week ${w}`).toBeNull()
    }
  })

  it('fires once, on the day the run reaches the number', () => {
    const n = buildMilestoneNotification(S(['2026-09-07']), 12, now)
    expect(n).toHaveLength(1)
    expect(n[0].body).toBe(milestoneNotification(12).body)
    expect(n[0].schedule.at.getTime()).toBeGreaterThan(now.getTime())
  })

  // Nothing records that a milestone was already said, so "the newest workout is today" is what
  // stops this firing on every re-sync. Re-syncing the same day is idempotent; the next day is not
  // this milestone's business.
  it('does not re-fire when nothing was logged today', () => {
    expect(buildMilestoneNotification(S(['2026-09-05', '2026-09-06']), 12, now)).toBeNull()
    expect(buildMilestoneNotification(S([]), 12, now)).toBeNull()
    expect(buildMilestoneNotification(null, 12, now)).toBeNull()
  })

  it('stays quiet when the streak is not on a milestone', () => {
    expect(buildMilestoneNotification(S(['2026-09-07']), 5, now)).toBeNull()
    expect(buildMilestoneNotification(S(['2026-09-07']), 0, now)).toBeNull()
  })
})
