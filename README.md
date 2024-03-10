# VMNotificationHandler

Notification handler provides a layer of abstraction into managing
notifications in your app.

Use the `shared` property to access a `NotificationHandler` instance. Here's
a list of it's capabilities:
* request authorization to send local notifications;
* monitor the authorization status;
* schedule notifications;
* remove both delivered and pending notifications.

The most common sequence of actions for an ideal usage is the following:

0. Set `shouldMonitorAuthorizationStatus` appropriately (default is `true`)
1. Call `requestAuthorization` (Scheduling a notification will make a
   request if one wasn't made until that point)
2. Check if `authorizationStatus` is as expected
    * React properly to non-ideal statuses
    * To have a SwiftUI View react immediately to authorization status' changes you need to observe the NotificationHandler instance by doing `@ObservedObject var notificationHandler = VMNotificationHandler.shared`
3. Call `scheduleNotification`
    * Optionally store the returned identifier to be able to remove the
      notification afterwards if necessary
    * The trigger time can be one of:
        * .after(TimeInterval): waits for the specified number of seconds
        * .at(Date): waits for the specified date
        * .now: schedules immediatelly

Remark: There's an *escape hatch* via the `notificationCenter` property
        that makes the current `UNUserNotificationCenter` instance available.
        The `authorizationStatus` and `shouldMonitorAuthorizationStatus` properties
        are `@Published` and their changes can be observed.

Author: Victor Martins
