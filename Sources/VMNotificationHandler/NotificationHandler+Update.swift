//
//  NotificationHandler+Convenience.swift
//  TemplatesAndSnippetsPlayground
//
//  Created by Victor Martins on 01/09/23.
//

import Foundation
import UserNotifications

// MARK: Update

public extension VMNotificationHandler {
    
    @discardableResult
    func update(
        notificationRequest: UNNotificationRequest,
        newTitle title: String? = nil,
        newSubtitle subtitle: String? = nil,
        newBody body: String? = nil,
        silenced: Bool? = nil,
        newTriggerTime: NotificationTime? = nil,
        newUserInfo userInfo: [AnyHashable: Any]? = nil
    ) async throws -> NotificationIdentifier {
        
        Self.logger.debug("Update notification request \(notificationRequest.identifier)")
        
        try self.validateNotificationProperties(title: title)
        
        let trigger: UNNotificationTrigger
        if let newTriggerTime {
            trigger = newTriggerTime.getNotificationTrigger()
        } else if let currentCalendarTrigger = notificationRequest.trigger as? UNCalendarNotificationTrigger {
            trigger = currentCalendarTrigger
        } else {
            let error: SchedulingError = .invalidTriggerForUpdate
            Self.logger.error("\(Self.errorMessage(for: error))")
            throw error
        }
        
        // Preparing the notification content
        guard var content = notificationRequest.content.mutableCopy() as? UNMutableNotificationContent else {
            let error: SchedulingError = .invalidContent
            Self.logger.error("\(Self.errorMessage(for: error))")
            throw error
        }
        
        try self.configureNotificationContent(
            &content,
            title: title,
            subtitle: subtitle,
            body: body,
            silenced: silenced,
            userInfo: userInfo
        )
        
        let request = UNNotificationRequest(
            identifier: notificationRequest.identifier,
            content: content,
            trigger: trigger
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
            return notificationRequest.identifier
        } catch {
            print("Error creating notification \(error)")
            throw SchedulingError.unknown(error)
        }
    }
    
}

// MARK: - Convenience

extension VMNotificationHandler {
    
    // Identifier
    @discardableResult
    func update(
        notificationWithIdentifier identifier: String,
        newTitle title: String? = nil,
        newSubtitle subtitle: String? = nil,
        newBody body: String? = nil,
        silenced: Bool? = nil,
        newTriggerTime: NotificationTime? = nil,
        newUserInfo userInfo: [AnyHashable: Any]? = nil
    ) async throws -> String {
        
        let notificationRequest = await self.getPendingNotification(withIdentifier: identifier)
        
        guard let notificationRequest else {
            let error: SchedulingError = .identifierNotFound
            Self.logger.error("\(Self.errorMessage(for: error))")
            throw error
        }
        
        return try await self.update(
            notificationRequest: notificationRequest,
            newTitle: title,
            newSubtitle: subtitle ,
            newBody: body,
            silenced: silenced,
            newTriggerTime: newTriggerTime,
            newUserInfo: userInfo
        )
    }
    
    // MARK: Reschedule
    
    // Trigger Time
    @discardableResult
    func reschedule(
        notificationRequest: UNNotificationRequest,
        triggerTime: NotificationTime
    ) async throws -> String {
        return try await self.update(notificationRequest: notificationRequest,
                                     newTriggerTime: triggerTime)
    }
    
    // Trigger Time
    @discardableResult
    func reschedule(
        notificationWithIdentifier identifier: NotificationIdentifier,
        triggerTime: NotificationTime
    ) async throws -> String {
        
        let notificationRequest = await self.getPendingNotification(withIdentifier: identifier)
        
        guard let notificationRequest else {
            let error: SchedulingError = .identifierNotFound
            Self.logger.error("\(Self.errorMessage(for: error))")
            throw error
        }
        
        return try await self.update(notificationRequest: notificationRequest,
                                     newTriggerTime: triggerTime)
    }
}
