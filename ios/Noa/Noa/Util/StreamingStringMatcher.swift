//
//  StreamingStringMatcher.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 6/16/23.
//
//  Helper class to scan a serial string stream for a substring match using a naive algorithm.
//

import Foundation

struct StreamingStringMatcher {
    private var temporaryString = ""
    private let target: String
    private(set) var charactersProcessed = 0

    init(lookingFor substring: String) {
        assert(substring.count >= 1)
        target = substring
    }

    /// Resets the matcher state by purging all accumulated data.
    mutating func reset() {
        temporaryString = ""
        charactersProcessed = 0
    }

    /// Ingests and appends string data and checks for a match in the current accumulated buffer.
    /// - Parameter afterAppending: String to accumulate before checking for match within all
    /// existing content.
    /// - Returns: True if an occurrence of the target substring exists. The target substring is
    /// then removed. Note that this means if the target string exists multiple times, subsequent
    /// calls will return true until all of the substrings are accounted for.
    mutating func matchExists(afterAppending string: String) -> Bool {
        temporaryString += string
        charactersProcessed += string.count

        // Look for possible substring match by locating the first character of the target string
        // inside the accumulated string
        while let idx = temporaryString.firstIndex(of: target[string.startIndex]) {
            let idxVal: Int = temporaryString.distance(from: temporaryString.startIndex, to: idx)

            // Have we accumulated enough characters for the target to possibly exist here? If so,
            // check for match.
            let targetEndIdxVal = idxVal + target.count
            guard targetEndIdxVal <= temporaryString.count else {
                // Insufficient characters to check, no match yet
                return false
            }
            let targetEndIdx = temporaryString.index(idx, offsetBy: target.count)
            if temporaryString[idx..<targetEndIdx] == target {
                // Match found. Remove everything up to end of target substring.
                temporaryString.removeSubrange(..<targetEndIdx)
                return true
            }

            // No match. Remove only up to and including the first character we started
            // checking from because target string may partially exist after it.
            temporaryString.removeSubrange(...idx)
        }

        // We can discard everything because the first character hasn't even been found yet
        temporaryString = ""
        return false
    }
}
