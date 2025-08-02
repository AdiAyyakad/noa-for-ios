//
//  ContentView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 7/23/23.
//
//  Top-level application view. Observers Controller (the app logic or "model", effectively) and
//  decides what to display.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var _settings: Settings
    @ObservedObject private var _controller: Controller

    /// Frame state (as reported by Controller)
    @State private var _isFrameConnected = false
    @State private var _frameWithinPairingRange = false   // only updated when no Frame yet paired

    /// Bluetooth state
    @State private var _bluetoothEnabled = false

    /// Controls whether device sheet displayed
    @State private var _showDeviceSheet = false

    /// Controls which device sheet is displayed, if showDeviceSheeet == true
    @State private var _deviceSheetType: DeviceSheetType = .pairing

    /// Update percentage
    @State private var _updateProgressPercent: Int = 0

    var body: some View {
        VStack {
            // Always show device management interface
            DeviceScreenView(
                showDeviceSheet: $_showDeviceSheet,
                deviceSheetType: $_deviceSheetType,
                frameWithinPairingRange: $_frameWithinPairingRange,
                updateProgressPercent: $_updateProgressPercent,
                bluetoothEnabled: $_bluetoothEnabled,
                onConnectPressed: { [weak _controller] in
                    _controller?.connectToNearest()
                }
            )
            .environmentObject(_settings)
            .onAppear {
                // Enable Bluetooth scanning when view appears
                if !_bluetoothEnabled {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        _bluetoothEnabled = true
                    }
                }
            }
        }
        .onAppear {
            // Initialize state
            _isFrameConnected = _controller.isFrameConnected
            _frameWithinPairingRange = _controller.nearestFrameID != nil
            _bluetoothEnabled = _controller.bluetoothEnabled

            // Always show device management interface 
            let (showDeviceSheet, deviceSheetType) = decideShowDeviceSheet()
            _showDeviceSheet = showDeviceSheet
            _deviceSheetType = deviceSheetType
        }
        .onChange(of: _controller.isFrameConnected) {
            // Sync connection state
            _isFrameConnected = $0
        }
        .onChange(of: _controller.nearestFrameID) {
            // Sync nearest Frame device ID
            _frameWithinPairingRange = $0 != nil
        }
        .onChange(of: _controller.bluetoothEnabled) {
            // Sync Bluetooth state
            _bluetoothEnabled = $0
        }
        .onChange(of: _bluetoothEnabled) {
            // Pass through to controller (will not cause a cycle because we monitor change only)
            _controller.bluetoothEnabled = $0
        }
        .onChange(of: _controller.frameState) { (value: Controller.FrameState) in
            // Update device sheet based on frame state
            let (showDeviceSheet, deviceSheetType) = decideShowDeviceSheet()
            _showDeviceSheet = showDeviceSheet
            _deviceSheetType = deviceSheetType
        }
        .onChange(of: _controller.updateProgressPercent) {
            _updateProgressPercent = $0
        }
    }

    init(settings: Settings, controller: Controller) {
        _settings = settings
        _controller = controller
    }

    private func decideShowDeviceSheet() -> (Bool, DeviceSheetType) {
        if _settings.pairedDeviceID == nil {
            // No Frame paired, show pairing sheet
            return (true, .pairing)
        }

        switch _controller.frameState {
        case .notReady:
            return (true, .pairing)    // show pairing sheet if disconnected
        case .updatingFirmware:
            return (true, .firmwareUpdate)
        case .updatingFPGA:
            return (true, .fpgaUpdate)
        case .ready:
            return (true, .pairing)    // show device management when connected
        }
    }
}
