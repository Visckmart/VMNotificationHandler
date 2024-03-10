//
//  NotificationHandler.swift
//
//  Created by Victor Martins on 29/10/22.
//  Updated by Victor Martins on 01/09/23.
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
/// * reschedule and change the content of pending notifications;
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
/// - Remark: The `authorizationStatus` and `shouldMonitorAuthorizationStatus` properties
///           are `@Published` and their changes can be observed.
///
/// - Author: Victor Martins
/// - Date: 2023-09-01
/// - Version: 1.1
@MainActor
public class VMNotificationHandler: NSObject, ObservableObject {
    
    // MARK: - Essentials
    
    /// Shared notification handler
    @MainActor public static var shared = VMNotificationHandler()
    
    /// Current notification center
    public static var notificationCenter: UNUserNotificationCenter { UNUserNotificationCenter.current() }
    public var notificationCenter: UNUserNotificationCenter { UNUserNotificationCenter.current() }
    
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Notifications")
    public typealias NotificationIdentifier = String
    
    // MARK: Authorization Status
    
    /// The current notification scheduling authorization status
    @MainActor @Published
    public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    /// Internal-usage boolean to suppress the animation on the first
    /// `authorizationStatus` property update
    private var isAuthorizationStatusUnknown = true
    
    /// Property that represents whether the `NotificationHandler` should
    /// monitor the notification scheduling authorization status.
    ///
    /// - Note: The monitoring is made by observing the application's
    /// `willEnterForegroundNotification` and refreshing the status.
    @MainActor @Published public var shouldMonitorAuthorizationStatus = true {
        didSet {
            willEnterForegroundMonitorTask?.cancel()
            
            if shouldMonitorAuthorizationStatus {
                willEnterForegroundMonitorTask = monitorAuthorizationStatus()
            }
        }
    }
    
    /// Task used to manage the authorization status monitoring
    private var willEnterForegroundMonitorTask: Task<(), Never>?
    
    
    // MARK: Initialization
    
    private override init() {
        super.init()
        
        // Setting up the delegate
        Self.notificationCenter.delegate = self
        
        // Setting up the monitoring, if needed
        Task {
            if shouldMonitorAuthorizationStatus {
                self.willEnterForegroundMonitorTask = self.monitorAuthorizationStatus()
            }
        }
        
        // Updating the authorization status for the first time
        Task { await self.updateAuthorizationStatus() }
    }
    
    // MARK: Authorization
    
    public func requestAuthorization() async {
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
    public func updateAuthorizationStatus() async -> UNAuthorizationStatus {
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
            
            let willEnterForegroundNotifications = NotificationCenter.default.notifications(
                named: UIApplication.willEnterForegroundNotification
            ).map { _ in () }
            for await _ in willEnterForegroundNotifications {
                await updateAuthorizationStatus()
            }
        }
    }
    
    // MARK: - Notification Scheduling
    
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
    public func scheduleNotification(
        identifier: NotificationIdentifier? = nil,
        title: String,
        subtitle: String? = nil,
        body: String? = nil,
        silenced: Bool = false,
        triggerTime: NotificationTime,
        repeats: Bool = false,
        userInfo: [AnyHashable: Any] = [:]
    ) async throws -> NotificationIdentifier {
        
        try self.validateNotificationProperties(
            title: title,
            triggerTime: triggerTime
        )
        
        // Preparing the notification content
        var content = UNMutableNotificationContent()
        try self.configureNotificationContent(
            &content,
            title: title,
            subtitle: subtitle,
            body: body,
            silenced: silenced,
            userInfo: userInfo
        )
        
        // Creating the notification request
        let identifier = identifier ?? UUID().uuidString
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: triggerTime.getNotificationTrigger(repeats: repeats)
        )
        
        // Checking for notification permissions
        await requestAuthorization()
        guard authorizationStatus == .authorized else {
            let error: SchedulingError = .notAuthorized
            Self.logger.error("\(Self.errorMessage(for: error))")
            throw error
        }
        
        do {
            try await Self.notificationCenter.add(request)
            return identifier
        } catch {
            let error: SchedulingError = .unknown(error)
            Self.logger.error("\(Self.errorMessage(for: error))")
            throw error
        }
    }
    
    
    // MARK: Notification Setup
    
    func validateNotificationProperties(
        title: String? = nil,
        triggerTime: NotificationTime? = nil
    ) throws {
        if let title {
            guard title.isEmpty == false else {
                let error: SchedulingError = .invalidTitle
                Self.logger.error("\(Self.errorMessage(for: error))")
                throw error
            }
        }
        
        if let triggerTime {
            guard triggerTime.isValid() else {
                let error: SchedulingError = .invalidTriggerForUpdate
                Self.logger.error("\(Self.errorMessage(for: error))")
                throw error
            }
        }
    }
    
    func configureNotificationContent(
        _ notificationContent: inout UNMutableNotificationContent,
        title: String?,
        subtitle: String?,
        body: String?,
        silenced: Bool?,
        userInfo: [AnyHashable: Any]?
    ) throws {
        let title = title ?? notificationContent.title
        guard title.isEmpty == false else {
            let error: SchedulingError = .invalidTitle
            Self.logger.error("\(Self.errorMessage(for: error))")
            throw error
        }
        notificationContent.title = title
        if let subtitle {
            notificationContent.subtitle = subtitle
        }
        if let body {
            notificationContent.body = body
        }
        if let silenced {
            notificationContent.sound = silenced ? nil : UNNotificationSound.default
        }
        if let userInfo {
            notificationContent.userInfo = userInfo
        }
    }
}

// MARK: - Utilities

extension VMNotificationHandler {
    
    public func getPendingNotification(withIdentifier identifier: NotificationIdentifier) async -> UNNotificationRequest? {
        let pendingRequests = await Self.notificationCenter.pendingNotificationRequests()
        
        if let referredNotificationRequest = pendingRequests.first(where: { $0.identifier == identifier }) {
            return referredNotificationRequest
        }
        
        return nil
    }
    
    static func errorMessage(for error: SchedulingError) -> String {
        return "\(error.localizedDescription) \(error.recoverySuggestion?.description ?? "")"
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
        return [.badge, .sound, .banner, .list]
    }
    
}
