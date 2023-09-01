//
//  NotificationHandler+SchedulingError.swift
//  TemplatesAndSnippetsPlayground
//
//  Created by Victor Martins on 01/09/23.
//

import Foundation

// MARK: Scheduling Error

extension VMNotificationHandler {
    
    public enum SchedulingError: Error, LocalizedError {
        case notAuthorized
        case invalidTitle
        case invalidContent
        case invalidTriggerTime
        case invalidTriggerForUpdate
        case identifierNotFound
        case unknown(any Error)
        
        public var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Not authorized to send notifications."
            case .invalidTitle:
                return "The requested notification title cannot be empty."
            case .invalidContent:
                return "The requested notification content is not valid."
            case .invalidTriggerTime:
                return "A trigger cannot be scheduled with a negative time interval."
            case .invalidTriggerForUpdate:
                return "A new date or a calendar trigger must originally be set on the notification request to allow for updates."
            case .identifierNotFound:
                return "Could not find a notification with the referred identifier."
            case .unknown(let error):
                return "An unknown error ocurred while trying to schedule the notification. \(error)"
            }
        }
        
        public var recoverySuggestion: String? {
            switch self {
            case .notAuthorized:
                return "Try checking the app's current notification authorization status."
            case .invalidTitle:
                return "Use a non-empty title. If you are updating a notification content, pass a nil value to keep the original."
            case .invalidContent:
                return "Check if the title is not empty and the trigger is in the future."
            case .invalidTriggerTime:
                return "Make sure to use a positive time interval on the trigger."
            case .invalidTriggerForUpdate:
                return "Make sure these requirements are being fulfilled."
            case .unknown:
                return nil
            default:
                return nil
            }
            
        }
    }
    
}
