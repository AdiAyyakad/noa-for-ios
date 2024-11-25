//
//  ControllerTests.swift
//  NoaTests
//
//  Created by Adi Ayyakad on 11/24/24.
//

@testable import Noa
import XCTest
/*
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

class MockChatService: ChatService {
    var responseToReturn: String?
    func sendMessage(_ message: String) async throws -> String {
        if let response = responseToReturn {
            return response
        }
        throw NSError(domain: "ChatError", code: 3, userInfo: nil)
    }
}

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
    
    func testPairDeviceSuccess() async {
        mockBluetoothManager.shouldReturnError = false
        
        await controller.pairDevice("Device1")
        
        XCTAssertEqual(controller.pairedDeviceID, "Device1")
        XCTAssertTrue(controller.isConnected)
    }

    func testPairDeviceFailure() async {
        mockBluetoothManager.shouldReturnError = true
        
        await controller.pairDevice("Device1")
        
        XCTAssertNil(controller.pairedDeviceID)
        XCTAssertFalse(controller.isConnected)
        XCTAssertTrue(controller.error?.contains("BluetoothError") ?? false)
    }
    
    func testChatResponse() async {
        let mockChatService = MockChatService()
        mockChatService.responseToReturn = "Success"
        
        await controller.handleChatResponse("Hello")
        
        XCTAssertEqual(controller.chatResponses.last, "Success")
    }

    func testChatResponseFailure() async {
        let mockChatService = MockChatService()
        mockChatService.responseToReturn = nil
        
        await controller.handleChatResponse("Hello")
        
        XCTAssertTrue(controller.error?.contains("ChatError") ?? false)
    }
    
    func testErrorHandlingBluetooth() async {
        mockBluetoothManager.shouldReturnError = true
        
        await controller.discoverDevices()
        
        XCTAssertTrue(controller.error?.contains("BluetoothError") ?? false)
    }

    func testErrorHandlingChat() async {
        let mockChatService = MockChatService()
        mockChatService.responseToReturn = nil
        
        await controller.handleChatResponse("Test Message")
        
        XCTAssertTrue(controller.error?.contains("ChatError") ?? false)
    }
    
    func testConnectDeviceSuccess() async {
        mockBluetoothManager.shouldReturnError = false
        
        // Simulate a successful connection to the device
        await controller.connectToDevice("Device1")
        
        XCTAssertTrue(controller.isConnected)
        XCTAssertEqual(controller.pairedDeviceID, "Device1")
    }

    func testConnectDeviceFailure() async {
        mockBluetoothManager.shouldReturnError = true
        
        // Simulate a failure to connect to the device
        await controller.connectToDevice("Device1")
        
        XCTAssertFalse(controller.isConnected)
        XCTAssertNil(controller.pairedDeviceID)
        XCTAssertTrue(controller.error?.contains("BluetoothError") ?? false)
    }
    
    func testDisconnectDevice() async {
        // Simulate a device being connected
        controller.pairedDeviceID = "Device1"
        controller.isConnected = true
        
        // Simulate disconnecting the device
        await controller.disconnectDevice()
        
        XCTAssertFalse(controller.isConnected)
        XCTAssertNil(controller.pairedDeviceID)
    }
    
    func testFirmwareUpdateStarted() async {
        // Assuming firmware update begins
        await controller.startFirmwareUpdate()
        
        XCTAssertTrue(controller.isFirmwareUpdating)
        XCTAssertEqual(controller.firmwareUpdateProgress, 0.0)
    }

    func testFirmwareUpdateProgress() async {
        // Simulate firmware update progress
        await controller.updateFirmwareProgress(0.5)  // 50% progress
        
        XCTAssertEqual(controller.firmwareUpdateProgress, 0.5)
    }

    func testFirmwareUpdateCompleted() async {
        // Simulate firmware update completion
        await controller.completeFirmwareUpdate()
        
        XCTAssertFalse(controller.isFirmwareUpdating)
        XCTAssertEqual(controller.firmwareUpdateProgress, 1.0)
    }
    
    func testMultipleDeviceDiscovery() async {
        // Mocking discovery of multiple devices
        mockBluetoothManager.discoverDevicesResult = [
            "Device1": -60,
            "Device2": -70,
            "Device3": -50
        ]
        
        await controller.discoverDevices()
        
        XCTAssertEqual(controller.discoveredDevices.count, 3)
        XCTAssertTrue(controller.discoveredDevices.keys.contains("Device1"))
        XCTAssertTrue(controller.discoveredDevices.keys.contains("Device2"))
        XCTAssertTrue(controller.discoveredDevices.keys.contains("Device3"))
    }
    
    func testChatMessageHandling() async {
        let mockChatService = MockChatService()
        
        // Mocking a chat response for a message
        mockChatService.responseToReturn = "Response to Hello"
        
        await controller.handleChatResponse("Hello")
        
        XCTAssertEqual(controller.chatResponses.last, "Response to Hello")
        
        // Test handling a different message
        mockChatService.responseToReturn = "Response to Goodbye"
        await controller.handleChatResponse("Goodbye")
        
        XCTAssertEqual(controller.chatResponses.last, "Response to Goodbye")
    }
    
    func testMultipleErrors() async {
        // Simulate Bluetooth error during device discovery
        mockBluetoothManager.shouldReturnError = true
        await controller.discoverDevices()
        
        XCTAssertTrue(controller.error?.contains("BluetoothError") ?? false)
        XCTAssertEqual(controller.discoveredDevices.count, 0)
        
        // Simulate ChatService error while sending a message
        let mockChatService = MockChatService()
        mockChatService.responseToReturn = nil  // Simulate failure
        await controller.handleChatResponse("Test")
        
        XCTAssertTrue(controller.error?.contains("ChatError") ?? false)
        XCTAssertEqual(controller.chatResponses.count, 0)
    }
    
    func testNoDevicesDiscovered() async {
        mockBluetoothManager.discoverDevicesResult = [:] // No devices found
        
        await controller.discoverDevices()
        
        XCTAssertEqual(controller.discoveredDevices.count, 0)
        XCTAssertTrue(controller.error?.contains("No devices found") ?? false)
    }
    
    func testRemovePairedDevice() async {
        // Simulate a paired device
        controller.pairedDeviceID = "Device1"
        controller.isConnected = true
        
        // Simulate removing the paired device
        await controller.removePairedDevice()
        
        XCTAssertNil(controller.pairedDeviceID)
        XCTAssertFalse(controller.isConnected)
    }
    
    func testDeviceConnectionTimeout() async {
        // Simulating a connection timeout situation
        mockBluetoothManager.shouldReturnError = true  // Timeout or connection failure
        
        await controller.connectToDevice("Device1")
        
        XCTAssertFalse(controller.isConnected)
        XCTAssertNil(controller.pairedDeviceID)
        XCTAssertTrue(controller.error?.contains("Connection Timeout") ?? false)
    }
    
    func testProcessChatCommand() async {
        let mockChatService = MockChatService()
        
        // Testing chat command processing for "status"
        mockChatService.responseToReturn = "Device is connected"
        await controller.handleChatResponse("status")
        
        XCTAssertEqual(controller.chatResponses.last, "Device is connected")
        
        // Testing chat command processing for "help"
        mockChatService.responseToReturn = "Here are the available commands: ..."
        await controller.handleChatResponse("help")
        
        XCTAssertEqual(controller.chatResponses.last, "Here are the available commands: ...")
    }func testUIUpdateOnStateChange() async {
        // Simulate pairing a device
        mockBluetoothManager.shouldReturnError = false
        await controller.pairDevice("Device1")
        
        // Check if the UI state for connection is updated
        XCTAssertTrue(controller.isConnected)
        XCTAssertEqual(controller.pairedDeviceID, "Device1")
    }
    
    func testMultipleDevicePairing() async {
        // Pairing the first device
        mockBluetoothManager.shouldReturnError = false
        await controller.pairDevice("Device1")
        
        XCTAssertEqual(controller.pairedDeviceID, "Device1")
        XCTAssertTrue(controller.isConnected)
        
        // Now simulate pairing a second device
        await controller.pairDevice("Device2")
        
        XCTAssertEqual(controller.pairedDeviceID, "Device2")
        XCTAssertTrue(controller.isConnected)
    }
    
    func testUnexpectedBluetoothDisconnect() async {
        // Simulate an initial device connection
        controller.pairedDeviceID = "Device1"
        controller.isConnected = true
        
        // Now simulate an unexpected disconnect (could be due to signal loss, etc.)
        await controller.handleBluetoothDisconnect()
        
        XCTAssertFalse(controller.isConnected)
        XCTAssertNil(controller.pairedDeviceID)
        XCTAssertTrue(controller.error?.contains("Bluetooth disconnected unexpectedly") ?? false)
    }
    
    func testLongOperationFeedback() async {
        // Simulate starting a firmware update
        await controller.startFirmwareUpdate()
        
        // Check if the UI feedback is correct
        XCTAssertTrue(controller.isFirmwareUpdating)
        XCTAssertEqual(controller.firmwareUpdateProgress, 0.0)
        
        // Simulate progress during the firmware update
        await controller.updateFirmwareProgress(0.5)  // 50% progress
        XCTAssertEqual(controller.firmwareUpdateProgress, 0.5)
        
        // Simulate update completion
        await controller.completeFirmwareUpdate()
        XCTAssertFalse(controller.isFirmwareUpdating)
        XCTAssertEqual(controller.firmwareUpdateProgress, 1.0)
    }
    
    func testStateRestoration() async {
        // Simulating a pairing process
        await controller.pairDevice("Device1")
        
        // Now simulate an app restart and state restoration
        controller.restoreState()  // Hypothetical method to restore state
        
        XCTAssertEqual(controller.pairedDeviceID, "Device1")
        XCTAssertTrue(controller.isConnected)
    }
    
    func testSimultaneousErrors() async {
        // Simulate Bluetooth error and ChatService error at the same time
        mockBluetoothManager.shouldReturnError = true
        let mockChatService = MockChatService()
        mockChatService.responseToReturn = nil  // Simulating failure
        
        // Simulate discovering devices and sending a chat message simultaneously
        await controller.discoverDevices()
        await controller.handleChatResponse("Test Message")
        
        XCTAssertTrue(controller.error?.contains("BluetoothError") ?? false)
        XCTAssertTrue(controller.error?.contains("ChatError") ?? false)
    }
}
*/
