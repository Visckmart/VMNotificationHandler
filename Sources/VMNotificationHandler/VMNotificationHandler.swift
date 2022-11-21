//
//  NotificationHandler.swift
//
//  Created by Victor Martins on 29/10/22.
//

import Foundation
import UserNotifications
import SwiftUI

/// Notification handler provides a layer of abstraction into managing
/// notifications in your app.
///
/// Use the `shared` property to access a `NotificationHandler` instance. Here's
/// a list of it's capabilities:
/// * request authorization to send local notifications;
/// * monitor the authorization status;
/// * schedule notifications;
/// * remove both delivered and pending notifications.
///
/// The most common sequence of actions for an ideal usage is the following:
///
/// 0. Set `shouldMonitorAuthorizationStatus` appropriately (default is `true`)
/// 1. Call `requestAuthorization` (Scheduling a notification will make a
///    request if one wasn't made until that point)
/// 2. Check if `authorizationStatus` is as expected
///     * React properly to non-ideal statuses
/// 3. Call `scheduleNotification`
///     * Optionally store the returned identifier to be able to remove the
///       notification afterwards if necessary
///
/// - Remark: There's an *escape hatch* via the `notificationCenter` property
///           that makes the current `UNUserNotificationCenter` instance available.
///           The `authorizationStatus` and `shouldMonitorAuthorizationStatus` properties
///           are `@Published` and their changes can be observed.
///
/// - Author: Victor Martins
/// - Date: 2022-11-20
/// - Version: 1.0
public class VMNotificationHandler: NSObject, ObservableObject {
    
    /// Shared notification handler
    static var shared = VMNotificationHandler()
    
    /// The current notification scheduling authorization status
    @MainActor @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// Internal-usage boolean to suppress the animation on the first
    /// `authorizationStatus` property update
    private var isAuthorizationStatusUnknown = true
    
    /// Property that represents whether the `NotificationHandler` should
    /// monitor the notification scheduling authorization status.
    ///
    /// - Note: The monitoring is made by observing the application's
    /// `willEnterForegroundNotification` and refreshing the status.
    @MainActor @Published var shouldMonitorAuthorizationStatus = true {
        didSet {
            print(shouldMonitorAuthorizationStatus, oldValue)
            willEnterForegroundMonitorTask?.cancel()
            
            if shouldMonitorAuthorizationStatus {
                willEnterForegroundMonitorTask = monitorAuthorizationStatus()
            }
        }
    }
    
    /// Task used to manage the authorization status monitoring
    private var willEnterForegroundMonitorTask: Task<(), Never>?
    
    /// Current notification center
    var notificationCenter: UNUserNotificationCenter {
        return UNUserNotificationCenter.current()
    }
    
    private override init() {
        super.init()
        
        // Setting up the delegate
        self.notificationCenter.delegate = self
        
        // Setting up the monitoring, if needed
        Task {
            if await shouldMonitorAuthorizationStatus {
                self.willEnterForegroundMonitorTask = self.monitorAuthorizationStatus()
            }
        }
        
        // Updating the authorization status for the first time
        Task { await self.updateAuthorizationStatus() }
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async {
        do {
            let options: UNAuthorizationOptions = [.alert, .badge, .sound]
            try await self.notificationCenter.requestAuthorization(options: options)
            await self.updateAuthorizationStatus()
        } catch {
            assertionFailure("Notification authorization request error \(error)")
            print("Notification authorization request error \(error)")
        }
    }
    
    /// Gets the current authorization status, updates the ``authorizationStatus``
    /// property and returns it.
    @discardableResult
    func updateAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        
        await MainActor.run {
            // Update the authorization status property.
            // If it's the first time, do so without animations.
            if self.isAuthorizationStatusUnknown {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    self.authorizationStatus = settings.authorizationStatus
                }
            } else {
                self.authorizationStatus = settings.authorizationStatus
            }
            
            self.isAuthorizationStatusUnknown = false
        }
        
        return settings.authorizationStatus
    }
    
    /// Starts monitoring the `UIApplication.willEnterForegroundNotification`
    /// in order to update the authorization status if the user left and is
    /// coming back to the app.
    private func monitorAuthorizationStatus() -> Task<Void, Never> {
        return Task {
            await updateAuthorizationStatus()
            for await _ in await NotificationCenter.default.notifications(
                named: UIApplication.willEnterForegroundNotification
            ) {
                print("willEnterForeground")
                await updateAuthorizationStatus()
            }
        }
    }
    
    
    // MARK: Scheduling Notifications
    
    /// Schedules a local notification with the provided information.
    /// - Parameters:
    ///   - identifier: The identifier of the notification. It can be used to
    ///                 remove it later. If no identifier is provided, a random
    ///                 one is generated and returned.
    ///   - title: The notification's primary description.
    ///   - subtitle: The subtitle can provide additional context.
    ///   - body: The body of the notification. Can have longer text than the
    ///           previous properties.
    ///   - silenced: Whether the notification is silenced or makes the
    ///               default sound.
    ///   - triggerTime: When the notification should be triggered. This can be
    ///                  stated both by specifying the after which time interval
    ///                  it should trigger, or at which date by making use of a
    ///                  ``NotificationTime`` object.
    /// - Throws: A ``SchedulingError``.
    /// - Returns: If the schedule is successful, it returns the scheduled
    ///            notification identifier.
    @discardableResult
    func scheduleNotification(
        identifier: String? = nil,
        title: String,
        subtitle: String? = nil,
        body: String? = nil,
        silenced: Bool = false,
        triggerTime: NotificationTime
    ) async throws -> String {
        guard title.isEmpty == false
                //                && subtitle == nil || subtitle?.isEmpty == false
                && triggerTime.isValid()
        else {
            assertionFailure("Identifier: \(identifier.debugDescription) Title: \(title.debugDescription) Trigger: \(triggerTime)")
            throw SchedulingError.invalidContent
        }
        
        await requestAuthorization()
        guard await authorizationStatus == .authorized else {
            throw SchedulingError.notAuthorized
        }
        
        // Preparing the notification content
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle {
            content.subtitle = subtitle
        }
        if let body {
            content.body = body
        }
        if silenced == false {
            content.sound = UNNotificationSound.default
        }
        
        let identifier = identifier ?? UUID().uuidString
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: triggerTime.getNotificationTrigger()
        )
        
        do {
            try await notificationCenter.add(request)
            return identifier
        } catch {
            print("Error creating notification \(error)")
            throw SchedulingError.unknown(error)
        }
    }
    
    
    // MARK: Removing notifications
    
    /// Removes multiple notifications via their identifiers.
    /// - Parameters:
    ///   - identifiers: An array of identifiers from the notifications that
    ///                  will be removed.
    ///   - evenIfPending: A boolean that specifies whether notifications that
    ///                    have not yet been delivered should also be removed.
    func removeNotifications(withIdentifiers identifiers: [String],
                             evenIfPending: Bool = true) {
        self.notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
        if evenIfPending {
            self.notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }
    
    /// Removes a notifications via it's identifier.
    /// - Parameters:
    ///   - identifier: The identifier from the notifications that will
    ///                 be removed.
    ///   - evenIfPending: A boolean that specifies whether the notification
    ///                    should be removed if it hasn't been delivered yet.
    func removeNotification(withIdentifier identifier: String,
                            evenIfPending: Bool = true) {
        self.removeNotifications(withIdentifiers: [identifier],
                                 evenIfPending: evenIfPending)
    }
    
    /// Removes all delivered notifications.
    func removeAllDeliveredNotifications() {
        self.notificationCenter.removeAllDeliveredNotifications()
    }
    
    /// Removes all pending notifications.
    func removeAllPendingNotifications() {
        self.notificationCenter.removeAllPendingNotificationRequests()
    }
    
    /// Removes all notifications, both delivered and pending.
    func removeAllNotifications() {
        self.removeAllDeliveredNotifications()
        self.removeAllPendingNotifications()
    }
}


// MARK: - Notification Time
extension VMNotificationHandler {
    
    enum NotificationTime {
        case after(TimeInterval)
        case at(Date)
        //        case around(DateComponents)
        
        func isValid() -> Bool {
            switch self {
            case .after(let timeInterval):
                let isValid = timeInterval > 0
                assert(isValid, "Time interval must be greater than 0")
                return isValid
            case .at(_):
                return true
            }
        }
        
        func getNotificationTrigger() -> UNNotificationTrigger {
            switch self {
            case .after(let timeInterval):
                return UNTimeIntervalNotificationTrigger(
                    timeInterval: timeInterval,
                    repeats: false
                )
            case .at(let date):
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second, .nanosecond],
                    from: date)
                return UNCalendarNotificationTrigger(dateMatching: components,
                                                     repeats: false)
            }
        }
    }
    
}

// MARK: - Scheduling Error
extension VMNotificationHandler {
    
    enum SchedulingError: Error, LocalizedError {
        case notAuthorized
        case invalidContent
        case unknown(Error)
        
        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Not authorized to send notifications."
            case .invalidContent:
                return "The requested notification content is not valid."
            case .unknown(let error):
                return "An unknown error ocurred while trying to schedule the notification. \(error)"
            }
        }
        
        var recoverySuggestion: String? {
            switch self {
            case .notAuthorized:
                return "Try checking the app's current notification authorization status."
            case .invalidContent:
                return "Check if the title is not empty and the trigger is in the future."
            case .unknown(_):
                return nil
            }
            
        }
    }
    
}

// MARK: - Notification Center Delegate
extension VMNotificationHandler: UNUserNotificationCenterDelegate {
    
    /// Asks the delegate how to handle a notification that arrived while the app
    /// was running in the foreground.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Shows the notification even on the foreground
        return [.badge, .sound, .banner, .list]
    }
    
    /// Asks the delegate to process the user's response to a delivered notification.
    /*
     func userNotificationCenter(
     _ center: UNUserNotificationCenter,
     didReceive response: UNNotificationResponse
     ) async {
     /*@START_MENU_TOKEN@*//*@PLACEHOLDER=...@*//*@END_MENU_TOKEN@*/
     }
     */
}

// MARK: - Debugging extensions

extension UNAuthorizationStatus: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unable to provide a description"
        }
    }
}
