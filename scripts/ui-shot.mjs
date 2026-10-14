// Screenshot the phone bundle in a chosen theme, through a real browser over CDP.
//
// The flatpak sandbox cannot see /tmp/opencode, so captures land under
// ~/.var/app/com.google.Chrome/design. Chrome is driven over the DevTools protocol rather than
// --screenshot so that localStorage can be seeded first: a fresh profile lands on the
// first-launch screen, and a design pass on the wrong screen is worthless.
//
//   node ui-shot.mjs <name> <theme> <accent> [tabIndex]
import { writeFileSync } from 'node:fs'

const PORT = 9446
const URL_ = 'http://localhost:8099/'
const sleep = ms => new Promise(r => setTimeout(r, ms))
const OUT = process.env.HOME + '/.var/app/com.google.Chrome/design'

let targets = null
for (let i = 0; i < 60; i++) {
  try {
    targets = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json()
    if (targets?.some(t => t.type === 'page')) break
  } catch {}
  await sleep(500)
}
const page = targets?.find(t => t.type === 'page')
if (!page) { console.error('no page target'); process.exit(1) }

const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
const logs = []
const send = (m, p = {}) => new Promise(r => { const n = ++id; pending.set(n, r); ws.send(JSON.stringify({ id: n, method: m, params: p })) })
await new Promise(r => ws.onopen = r)
ws.onmessage = e => {
  const m = JSON.parse(e.data)
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); return }
  if (m.method === 'Runtime.exceptionThrown') {
    logs.push(m.params.exceptionDetails.exception?.description ?? m.params.exceptionDetails.text)
  }
}

await send('Page.enable')
await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', {
  width: 393, height: 852, deviceScaleFactor: 2, mobile: true,
})

const ev = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
  return r?.result?.value
}

const [name = 'shot', theme = 'dark', accent = 'lime', tab = '0'] = process.argv.slice(2)

await send('Page.navigate', { url: URL_ })
await sleep(6000)

// Past the first-launch screen by seeding state with real content.
//
// The flag cannot be set directly: boot() recomputes needsMobileOnboarding as
// `!remote && !hasData(S)` (useStore.js:1910) on every load, so whatever localStorage says is
// overwritten. hasData is true as soon as S holds a routine, a workout or a weigh-in — which is
// also what a real user's state looks like after day one, so the screens captured here are the
// ones that will actually be seen.
await ev(`(() => {
  const k = 'gym_state_v1'
  const s = JSON.parse(localStorage.getItem(k) || '{}')
  s.routines = s.routines?.length ? s.routines : [
    { id: 'r1', name: 'Push', days: { 1: ['ex1'], 3: ['ex2'], 5: ['ex3'] }, ex: [{ id: 'ex1' }, { id: 'ex2' }, { id: 'ex3' }] },
  ]
  s.workouts = s.workouts?.length ? s.workouts : [
    { id: 'w1', d: '2026-10-12', name: 'Push', sets: [] },
    { id: 'w2', d: '2026-10-13', name: 'Pull', sets: [] },
  ]
  s.bodyweight = s.bodyweight?.length ? s.bodyweight : [{ d: '2026-10-13', kg: 78.4 }]
  s.theme = ${JSON.stringify(theme)}
  s.accent = ${JSON.stringify(accent)}
  localStorage.setItem(k, JSON.stringify(s))
})()`)
await send('Page.reload')
await sleep(7000)

if (Number(tab) > 0) {
  await ev(`(() => {
    const tabs = [...document.querySelectorAll('[role="tab"], nav button, .tabbar button, [class*="tab"]')]
    if (tabs[${Number(tab)}]) tabs[${Number(tab)}].click()
  })()`)
  await sleep(2500)
}

const shot = await send('Page.captureScreenshot', { format: 'png' })
writeFileSync(`${OUT}/${name}.png`, Buffer.from(shot.data, 'base64'))

console.log('file   :', `${OUT}/${name}.png`)
console.log('theme  :', await ev('document.documentElement.dataset.theme'))
console.log('accent :', await ev('document.documentElement.dataset.accent'))
console.log('accent colour:', await ev('getComputedStyle(document.documentElement).getPropertyValue("--acc").trim()'))
console.log('bg     :', await ev('getComputedStyle(document.body).backgroundColor'))
console.log('text   :', JSON.stringify(await ev('document.body.innerText.trim().slice(0,180)')))
if (logs.length) { console.log('ERRORS :'); logs.slice(0, 5).forEach(l => console.log('  ', l.slice(0, 200))) }
ws.close()
process.exit(0)