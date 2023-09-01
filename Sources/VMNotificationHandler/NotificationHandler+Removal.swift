//
//  Notifications+Removal.swift
//  TemplatesAndSnippetsPlayground
//
//  Created by Victor Martins on 01/09/23.
//

import Foundation

// MARK: Remove

extension VMNotificationHandler {
    
    // MARK: Specific
    
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
    
    
    // MARK: Generic
    
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
