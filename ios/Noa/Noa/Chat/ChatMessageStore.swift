//
//  ChatMessageStore.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/2/23.
//

import Combine
import SwiftUI

class ChatMessageStore: ObservableObject {
    @Published public var messages: [Message] = []

    public func putMessage(_ message: Message) {
        if let lastMessage = messages.last, lastMessage.typingInProgress {
            // Only the last message may be "typing in progress" indicator until supplanted by any other message
            messages[messages.count - 1] = message
        } else {
            messages.append(message)
        }
    }

    public func clear() {
        messages.removeAll()
    }

    public func minutesElapsed(from fromIndex: Int, to toIndex: Int) -> Double {
        if fromIndex < 0 {
            .infinity
        } else if toIndex >= messages.count {
            0
        } else {
            messages[fromIndex].timestamp.distance(to: messages[toIndex].timestamp) / 60
        }
    }
}
