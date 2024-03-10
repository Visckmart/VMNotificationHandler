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
        /// Waits for the specified date
        case at(Date)
        /// Schedules immediately
        public static var now: NotificationTime { NotificationTime.after(0.1) }
        
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
            case .after(let timeInterval) where timeInterval > 0:
                
                return UNTimeIntervalNotificationTrigger(timeInterval: timeInterval,
                                                         repeats: repeats)
            case .after:
                let soon = Date.now.addingTimeInterval(0.1)
                return NotificationTime.at(soon).getNotificationTrigger()
            
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
