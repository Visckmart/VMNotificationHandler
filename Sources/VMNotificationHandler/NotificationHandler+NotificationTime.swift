//
//  NotificationHandler+TriggerTime.swift
//  TemplatesAndSnippetsPlayground
//
//  Created by Victor Martins on 01/09/23.
//

import Foundation
import UserNotifications

// MARK: Notification Time

public extension VMNotificationHandler {
    
    enum NotificationTime {
        /// Waits for the specified TimeInterval
        case after(TimeInterval)
        
        /// Waits for the specified TimeInterval and reschedules it repeatedly
        case every(TimeInterval)
        
        /// Waits for the specified date
        case at(Date)
        
        /// Waits for a date that matches the specified date components
        case repeating(matchingComponents: DateComponents)
        
        /// Schedules immediately
        public static var now: NotificationTime { NotificationTime.after(0.1) }
        
        func isValid() -> Bool {
            switch self {
            case let .after(timeInterval):
                let isValid = timeInterval > 0
                assert(isValid, "Time interval must be greater than 0")
                return isValid
            case let .every(timeInterval):
                let isValid = timeInterval >= 60
                assert(isValid, "Time interval must be greater than 60 s for repeated notifications")
                return isValid
            case .at, .repeating:
                return true
            }
        }
        
        func getNotificationTrigger() -> UNNotificationTrigger {
            switch self {
            case .after(let timeInterval) where timeInterval > 0:
                return UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
                
            case .after:
                let soon = Date.now.addingTimeInterval(0.1)
                return NotificationTime.at(soon).getNotificationTrigger()
            
            case .every(let timeInterval):
                return UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: true)
            
            case .at(let date):
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second, .nanosecond],
                    from: date
                )
                return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            case let .repeating(matchingComponents):
                return UNCalendarNotificationTrigger(dateMatching: matchingComponents, repeats: true)
            }
        }
    }
    
}
