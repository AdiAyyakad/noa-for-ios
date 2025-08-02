//
//  DeviceScreenView.swift
//  Noa
//
//  Created by Artur Burlakin on 6/29/23.
//
//  This is the initial view on a fresh start when Moncole is unpaired and is used for device-
//  related operations: pairing, firmware update, FPGA update. Specific sheets are used for each
//  case.
//
//  Resources
//  ---------
//  - "Computed State in SwiftUI view"
//    https://yoswift.dev/swiftui/computed-state/
//

import SwiftUI

/// Device sheet types
enum DeviceSheetType {
    case pairing
    case firmwareUpdate
    case fpgaUpdate
}

struct DeviceScreenView: View {
    @EnvironmentObject private var _settings: Settings
    
    @Binding var showDeviceSheet: Bool
    @Binding var deviceSheetType: DeviceSheetType
    @Binding var frameWithinPairingRange: Bool
    @Binding var updateProgressPercent: Int
    @Binding var bluetoothEnabled: Bool
    @Environment(\.openURL) var openURL

    private let _onConnectPressed: (() -> Void)?
    
    var body: some View {
        ZStack {
            ColorModeAdaptiveView(
                light: Color(red: 242/255, green: 242/255, blue: 247/255),
                dark: Color(red: 28/255, green: 28/255, blue: 30/255)
            )
            .edgesIgnoringSafeArea(.all)

            VStack {
                VStack {
                    let light = Image("BrilliantLabsLogo")
                        .resizable()
                    let dark = Image("BrilliantLabsLogo_Dark")
                        .resizable()
                    ColorModeAdaptiveView(light: light, dark: dark)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 12)
                        .padding(.top, 80)
                    
                    Text("Noa")
                        .font(.system(size: 32, weight: .bold))
                        .padding(.top, -7)
                    
                    Spacer()
                
                    Text("Let’s set up your Frame. Take it out of the case, and bring it close.")
                        .font(.system(size: 15))
                        .frame(width: 314, height: 60)
                    
                    Spacer()

                    let privacyPolicyText = "Be sure to read our [Privacy Policy](https://brilliant.xyz/pages/privacy-policy) as well as [Terms and Conditions](https://brilliant.xyz/pages/terms-conditions) before using Noa."
                    Text(.init(privacyPolicyText))
                        .font(.system(size: 10))
                        .frame(width: 217)
                        .multilineTextAlignment(.center)
                        .accentColor(Color(red: 232/255, green: 46/255, blue: 135/255))
                        .lineSpacing(10)
                }

                VStack {
                    if showDeviceSheet {
                        RoundedRectangle(cornerRadius: 40)
                            .fill(Color.white)
                            .frame(height: 350)
                            .padding(10)
                            .overlay(
                                PopupDeviceView(
                                    showDeviceSheet: $showDeviceSheet,
                                    deviceSheetType: $deviceSheetType,
                                    frameWithinPairingRange: $frameWithinPairingRange,
                                    updateProgressPercent: $updateProgressPercent,
                                    onConnectPressed: _onConnectPressed
                                )
                            )
                    }
                }
            }
        }
        .ignoresSafeArea(.all)
    }

    init(showDeviceSheet: Binding<Bool>, deviceSheetType: Binding<DeviceSheetType>, frameWithinPairingRange: Binding<Bool>, updateProgressPercent: Binding<Int>, bluetoothEnabled: Binding<Bool>, onConnectPressed: (() -> Void)?) {
        _showDeviceSheet = showDeviceSheet
        _deviceSheetType = deviceSheetType
        _frameWithinPairingRange = frameWithinPairingRange
        _updateProgressPercent = updateProgressPercent
        _bluetoothEnabled = bluetoothEnabled
        _onConnectPressed = onConnectPressed
    }
}

struct DeviceScreenView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceScreenView(
            showDeviceSheet: .constant(true),
            deviceSheetType: .constant(.firmwareUpdate),
            frameWithinPairingRange: .constant(false),
            updateProgressPercent: .constant(50),
            bluetoothEnabled: .constant(true),
            onConnectPressed: { print("Connect pressed") }
        )
        .environmentObject(Settings())
    }
}
