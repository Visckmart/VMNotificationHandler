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
3. Call `scheduleNotification`
    * Optionally store the returned identifier to be able to remove the
      notification afterwards if necessary

- Remark: There's an *escape hatch* via the `notificationCenter` property
          that makes the current `UNUserNotificationCenter` instance available.
          The `authorizationStatus` and `shouldMonitorAuthorizationStatus` properties
          are `@Published` and their changes can be observed.

- Author: Victor Martins
- Date: 2022-11-20
- Version: 1.0
