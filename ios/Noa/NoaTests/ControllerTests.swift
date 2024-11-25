//
//  ControllerTests.swift
//  NoaTests
//
//  Created by Adi Ayyakad on 11/24/24.
//

@testable import Noa
import XCTest

class MockBluetoothManager: BluetoothManager {
    var shouldReturnError = false
    func discoverDevices() async throws -> [String: Int] {
        if shouldReturnError {
            throw NSError(domain: "BluetoothError", code: 1, userInfo: nil)
        }
        return ["Device1": -70, "Device2": -60]
    }

    func pairDevice(_ deviceID: String) async throws {
        if shouldReturnError {
            throw NSError(domain: "BluetoothError", code: 2, userInfo: nil)
        }
    }
}

//class MockChatService: ChatService {
//    var responseToReturn: String?
//    func sendMessage(_ message: String) async throws -> String {
//        if let response = responseToReturn {
//            return response
//        }
//        throw NSError(domain: "ChatError", code: 3, userInfo: nil)
//    }
//}

class ControllerTests: XCTestCase {
    var controller: Controller!
    var mockBluetoothManager: MockBluetoothManager!

    override func setUp() {
        super.setUp()
        mockBluetoothManager = MockBluetoothManager(autoConnectByProximity: true, peripheralName: "mock", services: [:], receiveCharacteristics: [:], transmitCharacteristics: [:], queue: .main)
        controller = Controller(settings: .init(), messages: ChatMessageStore())
    }

    func testDiscoverDevicesSuccess() async {
        mockBluetoothManager.shouldReturnError = false
        
        await controller.discoverDevices()
        
        XCTAssertEqual(controller.discoveredDevices.count, 2)
        XCTAssertTrue(controller.discoveredDevices.keys.contains("Device1"))
        XCTAssertTrue(controller.discoveredDevices.keys.contains("Device2"))
    }

    func testDiscoverDevicesFailure() async {
        mockBluetoothManager.shouldReturnError = true
        
        await controller.discoverDevices()
        
        XCTAssertTrue(controller.error?.contains("BluetoothError") ?? false)
        XCTAssertEqual(controller.discoveredDevices.count, 0)
    }
}
