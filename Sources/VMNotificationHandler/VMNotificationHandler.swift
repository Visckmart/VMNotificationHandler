//
//  NotificationHandler.swift
//
//  Created by Victor Martins on 29/10/22.
//

// TODO: Send the new features to the package, remove this file and use it as a package

import Foundation
import UserNotifications
import SwiftUI
import OSLog

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
    static var notificationCenter: UNUserNotificationCenter {
        return UNUserNotificationCenter.current()
    }
    
    private override init() {
        super.init()
        
        // Setting up the delegate
        Self.notificationCenter.delegate = self
        
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
            try await Self.notificationCenter.requestAuthorization(options: options)
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
        let settings = await Self.notificationCenter.notificationSettings()
        
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
        triggerTime: NotificationTime,
        repeats: Bool = false,
        userInfo: [AnyHashable: Any] = [:]
    ) async throws -> String {
        guard title.isEmpty == false
                && triggerTime.isValid()
        else {
            assertionFailure("Identifier: \(identifier.debugDescription) Title: \(title.debugDescription) Trigger: \(triggerTime)")
            throw SchedulingError.invalidContent
        }
        
        await requestAuthorization()
        guard await authorizationStatus == .authorized else {
            let error: SchedulingError = .notAuthorized
            Self.logger.error("\(Self.errorMessage(for: error))")
            throw error
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
        if userInfo.isEmpty == false {
            content.userInfo = userInfo
        }
        if silenced == false {
            content.sound = UNNotificationSound.default
        }
        
        let identifier = identifier ?? UUID().uuidString
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: triggerTime.getNotificationTrigger(repeats: repeats)
        )
        
        do {
            try await Self.notificationCenter.add(request)
            return identifier
        } catch {
            let error: SchedulingError = .unknown(error)
            Self.logger.error("\(Self.errorMessage(for: error))")
            throw error
        }
    }
    
    
    @discardableResult
    func rescheduleNotificationRequest(
        notificationRequest: UNNotificationRequest,
        triggerTime: NotificationTime,
        repeats: Bool = false
    ) async throws -> String {
        guard notificationRequest.content.title.isEmpty == false
                && triggerTime.isValid()
        else {
            assertionFailure("Identifier: \(notificationRequest.identifier.debugDescription) Title: \(notificationRequest.content.title.debugDescription) Trigger: \(triggerTime)")
            throw SchedulingError.invalidContent
        }
        
        await requestAuthorization()
        guard await authorizationStatus == .authorized else {
            throw SchedulingError.notAuthorized
        }
        
        // Preparing the notification content
        let content = notificationRequest.content
        
        let identifier = notificationRequest.identifier
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: triggerTime.getNotificationTrigger(repeats: repeats)
        )
        
        do {
            try await Self.notificationCenter.add(request)
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
        Self.notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
        if evenIfPending {
            Self.notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }
    
    static let logger = Logger(subsystem: "com.visckmart.TemplatesAndSnippetsPlayground", category: "Notifications")
    
    private static func errorMessage(for error: SchedulingError) -> String {
        return "\(error.localizedDescription) \(error.recoverySuggestion?.description ?? "")"
    }
    
    
    
    @discardableResult
    func update(
        withIdentifier identifier: String,
        newTitle title: String? = nil,
        newSubtitle subtitle: String? = nil,
        newBody body: String? = nil,
        silenced: Bool? = nil,
        newTriggerTime: Date? = nil,
        newUserInfo userInfo: [AnyHashable: Any]? = nil
    ) async throws -> String {
        let pendingRequests = await Self.notificationCenter.pendingNotificationRequests()
        
        guard let referredNotificationRequest = pendingRequests.first(where: { $0.identifier == identifier }) else {
            let error: SchedulingError = .invalidTriggerForUpdate
            Self.logger.error("\(Self.errorMessage(for: error))")
            throw error
        }
        
        return try await self.update(
            notificationRequest: referredNotificationRequest,
            newTitle: title,
            newSubtitle: subtitle ,
            newBody: body,
            silenced: silenced,
            newTriggerTime: newTriggerTime,
            newUserInfo: userInfo
        )
    }
    
    @discardableResult
    func update(
        notificationRequest: UNNotificationRequest,
        newTitle title: String? = nil,
        newSubtitle subtitle: String? = nil,
        newBody body: String? = nil,
        silenced: Bool? = nil,
        newTriggerTime: Date? = nil,
        newUserInfo userInfo: [AnyHashable: Any]? = nil
    ) async throws -> String {
        
        Self.logger.debug("Update notification request \(notificationRequest.identifier)")
        
        let trigger: UNCalendarNotificationTrigger
        if let newTriggerTime {
            trigger = UNCalendarNotificationTrigger(fromSpecificDate: newTriggerTime)
        } else if let currentCalendarTrigger = notificationRequest.trigger as? UNCalendarNotificationTrigger {
            trigger = currentCalendarTrigger
        } else {
            let error: SchedulingError = .invalidTriggerForUpdate
            Self.logger.error("\(Self.errorMessage(for: error))")
            throw error
        }
        
        await requestAuthorization()
        guard await authorizationStatus == .authorized else {
            let error: SchedulingError = .notAuthorized
            Self.logger.error("\(Self.errorMessage(for: error))")
            throw error
        }
        
        // Preparing the notification content
        guard let content = notificationRequest.content.mutableCopy() as? UNMutableNotificationContent else {
            let error: SchedulingError = .invalidContent
            Self.logger.error("\(Self.errorMessage(for: error))")
            throw error
        }
        
        if let title {
            guard title.isEmpty == false else {
                let error: SchedulingError = .invalidTitle
                Self.logger.error("\(Self.errorMessage(for: error))")
                throw error
            }
            content.title = title
        }
        if let subtitle {
            content.subtitle = subtitle
        }
        if let body {
            content.body = body
        }
        if let silenced {
            content.sound = silenced ? nil : UNNotificationSound.default
        }
        if let userInfo {
            content.userInfo = userInfo
        }
        
        let request = UNNotificationRequest(
            identifier: notificationRequest.identifier,
            content: content,
            trigger: trigger
        )
        
        do {
            try await Self.notificationCenter.add(request)
            return notificationRequest.identifier
        } catch {
            print("Error creating notification \(error)")
            throw SchedulingError.unknown(error)
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
        Self.notificationCenter.removeAllDeliveredNotifications()
    }
    
    /// Removes all pending notifications.
    func removeAllPendingNotifications() {
        Self.notificationCenter.removeAllPendingNotificationRequests()
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
            case .at:
                return true
            }
        }
        
        func getNotificationTrigger(repeats: Bool = false) -> UNNotificationTrigger {
            switch self {
            case .after(let timeInterval):
                return UNTimeIntervalNotificationTrigger(
                    timeInterval: timeInterval,
                    repeats: repeats
                )
            case .at(let date):
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second, .nanosecond],
                    from: date)
                return UNCalendarNotificationTrigger(dateMatching: components,
                                                     repeats: repeats)
            }
        }
    }
    
}

extension UNCalendarNotificationTrigger {
    convenience init(fromSpecificDate date: Date) {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
        self.init(dateMatching: components, repeats: false)
    }
}

// MARK: - Scheduling Error
extension VMNotificationHandler {
    
    enum SchedulingError: Error, LocalizedError {
        case notAuthorized
        case invalidTitle
        case invalidContent
        case invalidTriggerForUpdate
        case unknown(any Error)
        
        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Not authorized to send notifications."
            case .invalidTitle:
                return "The requested notification title cannot be empty."
            case .invalidContent:
                return "The requested notification content is not valid."
            case .invalidTriggerForUpdate:
                return "A new date or a calendar trigger must originally be set on the notification request to allow for updates."
            case .unknown(let error):
                return "An unknown error ocurred while trying to schedule the notification. \(error)"
            }
        }
        
        var recoverySuggestion: String? {
            switch self {
            case .notAuthorized:
                return "Try checking the app's current notification authorization status."
            case .invalidTitle:
                return "Use a non-empty title. If you are updating a notification content, pass a nil value to keep the original."
            case .invalidContent:
                return "Check if the title is not empty and the trigger is in the future."
            case .invalidTriggerForUpdate:
                return "Make sure these requirements are being fulfilled."
            case .unknown:
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
        //        let notificationData = notification.request.content.userInfo
        //        print(notificationData)
        // Shows the notification even on the foreground
        return [.badge, .sound, .banner, .list]
    }
    
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

extension VMNotificationHandler {
    func getAllNotifications() async -> [UNNotificationRequest] {
        var nofitications: [UNNotificationRequest] = []
        
        let requests = await Self.notificationCenter.pendingNotificationRequests()
        print("Pending notifications:")
        for request in requests {
            print(request.content.title)
            nofitications.append(request)
        }
        
        return nofitications
        
    }
}
