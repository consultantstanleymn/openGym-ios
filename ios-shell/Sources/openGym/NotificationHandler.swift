import Foundation
import UserNotifications

// LocalNotifications.
//
// openGym keeps a rolling window of scheduled notifications rather than one at a time
// (REMINDER_WINDOW_DAYS = 60 daily workout reminders, NUDGE_WINDOW_DAYS = 7 missed-workout
// nudges) and cancels the whole window before rebuilding it on every sync. So:
//
//   - cancelling an id that was never scheduled is a normal outcome, not an error. If it threw,
//     syncReminder's catch would swallow it and the window would never be rebuilt.
//   - pending notification requests are capped at 64 by iOS. A 67-id window is under that, but
//     the cap is why the cancel-all-then-reschedule shape exists at all.
//
// The rest timer is not here: it is RestAlert, an Android foreground service that keeps the
// countdown alive and sounds with the screen locked. iOS has no equivalent, and lib/rest-alert.js
// already resolves it to null on iOS and falls back to this handler's scheduled notification.

@MainActor
struct NotificationHandler: NativePlugin {

    var methods: [String: ([String: Any]) throws -> Any] {
        ["checkPermissions": checkPermissions,
        "requestPermissions": requestPermissions,
        "schedule": schedule,
        "cancel": cancel,
        "getPending": getPending,
        ]
    }

    private let center = UNUserNotificationCenter.current()

    func checkPermissions(_ args: [String: Any]) throws -> Any {
        // Synchronous because the JS side awaits this and branches on `display`. The settings
        // query is cheap and the alternative is a callback that has to be bridged back.
        var display = "prompt"
        let semaphore = DispatchSemaphore(value: 0)
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: display = "granted"
            case .denied: display = "denied"
            case .notDetermined: display = "prompt"
            @unknown default: display = "prompt"
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
        return ["display": display]
    }

    func requestPermissions(_ args: [String: Any]) throws -> Any {
        var display = "denied"
        let semaphore = DispatchSemaphore(value: 0)
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            display = granted ? "granted" : "denied"
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        return ["display": display]
    }

    func schedule(_ args: [String: Any]) throws -> Any {
        for entry in args.array("notifications") {
            guard let item = entry as? [String: Any],
                  let id = item.int("id"),
                  let title = item.string("title"),
                  let body = item.string("body"),
                  let at = item.dict("schedule").date("at")
            else {
                throw NativeError("a notification needs id, title, body and schedule.at")
            }
            guard at > Date() else { continue }   // a time already past is never worth queueing

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: at)
            // A calendar trigger, not an interval: these are "08:00 on this day", and an interval
            // would drift and would still fire while the app is uninstalled on the wrong day.
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let request = UNNotificationRequest(
                identifier: String(id), content: content, trigger: trigger)
            center.add(request)
        }
        return [:]
    }

    func cancel(_ args: [String: Any]) throws -> Any {
        let ids = args.array("notifications")
            .compactMap { ($0 as? [String: Any])?.int("id") }
            .map(String.init)
        if ids.isEmpty {
            center.removeAllPendingNotificationRequests()
        } else {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        return [:]
    }

    func getPending(_ args: [String: Any]) throws -> Any {
        var out: [[String: Any]] = []
        let semaphore = DispatchSemaphore(value: 0)
        center.getPendingNotificationRequests { requests in
            for r in requests {
                if let id = Int(r.identifier) {
                    out.append([
                        "id": id,
                        "title": r.content.title,
                        "body": r.content.body,
                    ])
                }
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
        return ["notifications": out]
    }
}