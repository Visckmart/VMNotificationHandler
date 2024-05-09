//
//  Notifications+Removal.swift
//  TemplatesAndSnippetsPlayground
//
//  Created by Victor Martins on 01/09/23.
//

import Foundation

// MARK: Remove

public extension VMNotificationHandler {
    
    enum NotificationState {
        /// Notifications that have already been delivered to the user
        case delivered
        
        /// Notifications that are waiting to be delivered to the user
        case pending
        
        /// Notifications that both have already been delivered and are waiting to be delivered
        /// to the user
        case deliveredAndPending
    }
    
    // MARK: Specific
    
    /// Removes multiple notifications via their identifiers.
    /// - Parameters:
    ///   - identifiers: An array of identifiers from the notifications that
    ///                  will be removed.
    ///   - evenIfPending: A boolean that specifies whether notifications that
    ///                    have not yet been delivered should also be removed.
    func removeNotifications(withIdentifiers identifiers: [String],
                             from notificationState: NotificationState = .deliveredAndPending) {
        if notificationState == .delivered || notificationState == .deliveredAndPending {
            Self.notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
        if notificationState == .pending || notificationState == .deliveredAndPending {
            Self.notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }
    
    /// Removes a notifications via it's identifier.
    /// - Parameters:
    ///   - identifier: The identifier from the notifications that will
    ///                 be removed.
    ///   - evenIfPending: A boolean that specifies whether the notification
    ///                    should be removed if it hasn't been delivered yet.
    func removeNotification(withIdentifier identifier: String,
                            from notificationState: NotificationState = .deliveredAndPending) {
        self.removeNotifications(withIdentifiers: [identifier], from: notificationState)
    }
    
    
    // MARK: Generic
    
    /// Removes all notifications, both delivered and pending.
    func removeAllNotifications(from notificationState: NotificationState) {
        if notificationState == .delivered || notificationState == .deliveredAndPending {
            Self.notificationCenter.removeAllDeliveredNotifications()
        }
        if notificationState == .pending || notificationState == .deliveredAndPending {
            Self.notificationCenter.removeAllPendingNotificationRequests()
        }
    }
}
