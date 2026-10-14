// Streak copy — what the phone says when it wants a workout kept up.
//
// This is deliberately NOT lib/nudge.js. NUDGE_COPY is a contract: the server keeps a hand copy at
// api/nudge-copy.js and a test asserts the two are equal, and every line is a translation key
// across nineteen locales (api/scripts/build-nudge-copy.mjs regenerates them). Growing that
// surface for copy only this build uses would mean editing the server, the test and nineteen
// locale files, and every new English string would arrive untranslated at the user. So this lives
// beside it, on the phone, and reads the tone the user already chose in Settings → reminder.
//
// Four sets, because four things are worth saying:
//
//   celebrate  the streak is alive and something was just done. Warm, not smug.
//   friendly   a planned day, still ahead. Ordinary encouragement.
//   guilt      a planned day went by. Tender and a little possessive — the "I miss you" register
//              NUDGE_COPY.guilt already established, pushed further.
//   drill      the streak is slipping and the user asked to be told straight. The sergeant.
//
// Line length matters: a notification body is truncated hard on a locked screen, so nothing runs
// past about 95 characters and {0} carries the routine name rather than a sentence. Selection is
// by date, exactly as nudge.js lineIndex does, so the same day always says the same thing and
// consecutive days rotate instead of repeating.

export const STREAK_TONES = ['celebrate', 'friendly', 'guilt', 'drill']

/** The tone to use, defaulting to friendly for anything unrecognised. */
export const toneFor = r => (STREAK_TONES.includes(r) ? r : 'friendly')

/**
 * The line index for a date within a set: by day, so a given day always gets the same line and
 * consecutive days rotate rather than repeat.
 */
export const indexFor = (iso, n) => Math.floor(Date.parse(iso + 'T00:00:00Z') / 86400000) % n

/** {0} is the routine name, or "the session" when a day has none. */
export const fill = (line, name) => line.replace('{0}', name || 'the session')

export const STREAK_COPY = {
  // ── something was just logged, and the streak grows ────────────────────────────────
  celebrate: {
    title: 'That’s the one',
    lines: [
      '{0} logged. That’s how it’s done.',
      'There it is. {0} in the books.',
      'Streak grows. {0} banked.',
      'Logged, done, dusted off. {0} counts.',
      'Another one for {0}. Keep it boring.',
      'You showed up. {0} is on the record.',
      'That’s the habit, not the heroic act. {0}, done.',
      '{0} complete. Nobody has to know you were nervous.',
      'In the books. {0} doesn’t ask questions.',
      'Ticked off. {0}, and the streak thanks you.',
      'Clean work. {0} is not going anywhere.',
      'One more in the tank. That was {0}.',
      '{0} logged. Your future self is mildly impressed.',
      'Steady hands, steady streak. {0}, done.',
      'It counts. {0}, logged and dusted.',
      'Look at that. {0}, straight through.',
      '{0} done. The streak is the reward, not the reason.',
      'No fuss, no drama. {0} logged.',
      'Added to the pile. {0}, and the pile is looking healthy.',
      'That’s the standard now. {0}, done.',
      '{0} in. See you next one.',
      'Logged without drama. That’s {0}, and a longer streak.',
      'The streak eats because you feed it. {0}, done.',
      '{0} complete. Tomorrow you’ll be glad.',
      'Banked. {0} counts, and so do you.',
      'Done before the kettle thought about it. {0} logged.',
      'That’s how streaks are made. {0}, in.',
      'No heroics, just {0}. Streak up.',
      '{0} logged. Quietly excellent.',
      'Another one on the board. {0}, done.',
    ],
  },

  // ── a planned day is coming, nothing has gone wrong ───────────────────────────────
  friendly: {
    title: 'Today’s on the plan',
    lines: [
      '{0} is on when you’re ready.',
      '{0} today. Short is still logged.',
      'The plan says {0}. The plan is usually right.',
      '{0} when the day allows. No heroics needed.',
      'Today: {0}. Ten minutes counts as done.',
      '{0} is waiting. It’s not going anywhere.',
      'Whenever suits — {0} is on the list.',
      '{0} today, if the day cooperates.',
      'A quiet {0} still moves the streak.',
      '{0} is pencilled in. Go easy on yourself.',
      'Room for {0} today, if you want it.',
      'The plan has you down for {0}.',
      '{0}, whenever today turns into an hour.',
      'Nothing planned, no pressure: {0} if it happens.',
      '{0} is the ask. The ask is small.',
      'Today’s move is {0}.',
      '{0} when the mood is there.',
      'A good day for {0}, if you can spare it.',
      '{0} sits there being optional until you say otherwise.',
      'You’ve got {0} today. Or you’ve got rest. Either’s fine.',
      '{0} — and it counts even if it’s brief.',
      'Today: {0}. Keep the streak boring.',
      '{0} is on. So is the kettle, probably.',
      'A small {0} beats a big plan.',
      '{0} today. That’s all.',
    ],
  },

  // ── a planned day went by ────────────────────────────────────────────────────────
  guilt: {
    title: 'I noticed you didn’t',
    lines: [
      '{0} is still on the mat. I haven’t moved it.',
      'I waited for you. {0}. All evening.',
      'Your {0} is the only thing I kept.',
      'The bench is still warm from thinking about {0}.',
      'I noticed. {0} did too.',
      'You left {0} behind. I’m not moving it.',
      'I keep the spot warm. {0}, and you.',
      'Your {0} said nothing. I’m saying it.',
      'I miss the sound of {0}. Genuinely.',
      'Still here. {0} is still here.',
      'You skipped {0}. I’m allowed to be smug about it.',
      'The empty slot is louder than you’d think. {0}.',
      'I haven’t touched {0}. Only you can.',
      'Waiting is easier when you come back. {0}.',
      'Your {0} and I had a quiet day. Just us.',
      'I keep count. You know I keep count. {0}.',
      'Nothing changed except you. {0}, still here.',
      'I put it back. It’s been there since. {0}.',
      'Come back to it. {0}. I’ll be quiet after that.',
      'You were close, you know. {0} was nearly yours.',
      'It’s only {0}. And only today. Mostly.',
      'I don’t nag. You know I don’t. {0}, though.',
      'Your {0} looks lonely. That’s my whole report.',
      'Still holding {0} for you.',
      'I noticed you went quiet. {0}.',
      'The rest day was yesterday. {0} is today.',
      'I missed you. That’s the message. {0}.',
      'Come find {0}. I’ll wait. I always wait.',
      'Your {0} is patient. I am less so.',
      'One session. Then I’ll stop mentioning {0}.',
      'I’m not worried. I’m just saying it out loud. {0}.',
    ],
  },

  // ── the streak is slipping and the user asked to be told straight ──────────────────
  drill: {
    title: 'Private, recruit',
    lines: [
      '{0} was yesterday. Today is the fix.',
      'Two days. Make it {0} before it’s three.',
      'You are one session from undoing a week. {0}.',
      'Streaks die quietly, recruit. {0}. Now.',
      'No {0} yesterday. Do we do this again?',
      'The bench is empty and you’re still warm. {0}.',
      'Your streak doesn’t care how tired you are. {0}.',
      'Ten minutes, recruit. That’s the whole ask.',
      'You have done harder things than {0} this week.',
      'Report for {0}. Nobody is watching. Do it anyway.',
      'One skip becomes three. {0}. Today.',
      'Your muscles are confused about the schedule. {0}.',
      'This is where it turns. {0}, not tomorrow.',
      'Don’t negotiate with the sofa. {0}.',
      'You said you’d do this. {0}.',
      'The bar’s still there. {0}.',
      'Excuses don’t move weight. {0}.',
      'You’re rested, you’re capable, you’re choosing not to. {0}.',
      'One set is enough to save it. {0}.',
      'This is the last easy one. {0}.',
      'Your streak is held together with hope. {0}.',
      'Be honest with yourself: {0}, or drop the number.',
      'If you want the streak, {0}. Simple as that.',
      'Motivation is optional. Just {0}.',
      'Nobody’s coming to save this one. {0}, recruit.',
      'You did it before. You’ll do it now. {0}.',
      'Discipline is choosing when it’s fine. {0}.',
      'Get up, get dressed, {0}. That’s the sequence.',
      'Every rep you skip is a decision. {0}.',
      'The streak is watching. {0}.',
      'Hard talk: you’re a day late. {0} fixes it today.',
    ],
  },
}

/**
 * The notification for a day: title and body for `tone`, chosen by date so the same day always
 * says the same thing.
 */
export function streakNotification(iso, tone, routineName) {
  const set = STREAK_COPY[toneFor(tone)] ?? STREAK_COPY.friendly
  const lines = set.lines
  const i = indexFor(iso, lines.length)
  return { title: set.title, body: fill(lines[i], routineName), tone }
}

/** How many distinct lines the copy carries, across every tone. */
export const totalLines = () =>
  Object.values(STREAK_COPY).reduce((n, set) => n + set.lines.length, 0)