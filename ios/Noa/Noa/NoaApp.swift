//
//  NoaApp.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/1/23.
//

import Combine
import SwiftUI

@main
struct NoaApp: App {
    private let _settings = Settings()
    private var _controller: Controller!

    var body: some Scene {
        WindowGroup {
            ContentView(
                settings: _settings,
                controller: _controller
            )
        }
    }

    init() {
        _controller = Controller(settings: _settings)
    }
}
