// LocalNotifications, and App for the foreground callbacks that go with it.
//
// openGym schedules two windows of local notifications and cancels both wholesale on every
// sync (lib/mobile.js syncReminder): 60 daily workout reminders plus 7 missed-workout nudges. The
// cancel list therefore names up to 67 ids that may never have been scheduled, so cancelling an
// unknown id is a no-op on the native side rather than an error — otherwise every sync would
// reject and the reminder would never be (re)scheduled.
import { call, on } from './bridge.js'

export const LocalNotifications = {
  async checkPermissions() {
    const r = await call('LocalNotifications', 'checkPermissions', {})
    return { display: r.display || 'prompt' }
  },
  async requestPermissions() {
    const r = await call('LocalNotifications', 'requestPermissions', {})
    return { display: r.display || 'denied' }
  },
  async schedule({ notifications } = {}) {
    // schedule.at is a Date. bridge.encode turns it into { '@date': ms }, which the Swift side
    // reads back as a DateComponents for UNCalendarNotificationTrigger.
    await call('LocalNotifications', 'schedule', { notifications: notifications || [] })
  },
  async cancel({ notifications } = {}) {
    await call('LocalNotifications', 'cancel', { notifications: notifications || [] })
  },
  async getPending() {
    const r = await call('LocalNotifications', 'getPending', {})
    return { notifications: r.notifications || [] }
  },
}

// App is used for one thing: appStateChange, so the app can resync the reminder window and pull
// account state when it returns to the foreground. backButton is Android-only.
export const App = {
  async addListener(event, listener) {
    // No closure crosses the boundary. The page registers here by event name, and the shell
    // pushes {event, payload} to ogEvents when the app changes state — see AppSchemeHandler's
    // sibling, EventSink in AppDelegate.swift, and the dispatch table in bridge.js. That keeps
    // addListener safe to call more than once, which lib/mobile.js does on every launch.
    const unsubscribe = on(event, payload => listener(payload))
    const r = await call('App', 'addListener', { event })
    return {
      id: r.id,
      remove: async () => {
        unsubscribe()
        await call('App', 'removeListener', { id: r.id }).catch(() => {})
      },
    }
  },
  async removeAllListeners() {
    await call('App', 'removeAllListeners', {})
  },
  async exitApp() {
    await call('App', 'exitApp', {})
  },
  async getInfo() {
    return call('App', 'getInfo', {})
  },
  async getLaunchUrl() {
    return call('App', 'getLaunchUrl', {})
  },
}