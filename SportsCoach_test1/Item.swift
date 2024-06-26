//
//  Item.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/2.
//

import Foundation
import SwiftData

@available(iOS 17, *)
@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
