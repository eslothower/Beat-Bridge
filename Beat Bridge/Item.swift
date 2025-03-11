//
//  Item.swift
//  Beat Bridge
//
//  Created by Eli Slothower on 3/11/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
