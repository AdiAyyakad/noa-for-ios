//
//  PairingSheetView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 7/23/23.
//

import SwiftUI

struct PopupDeviceView: View {
    @Binding var showDeviceSheet: Bool
    @Binding var deviceSheetType: DeviceSheetType
    @Binding var frameWithinPairingRange: Bool
    @Binding var updateProgressPercent: Int
    private let _onConnectPressed: (() -> Void)?
    
    //Video logic
    @State private var triggerUpdate = false
    let frameIcon = UIImage(named: "FrameIcon")
    
    var body: some View {
        ZStack {
            // Cancel button
            VStack {
                HStack {
                    Spacer()

                    if deviceSheetType == .pairing {
                        // Only the pairing sheet may be dismissed. Updates cannot be interrupted
                        // and the app would be in an undefined state if the device sheet was
                        // hidden while an update was in progress.
                        Button {
                            showDeviceSheet = false
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 116/255, green: 116/255, blue: 128/255).opacity(0.08))
                                    .frame(width: 22, height: 22)

                                Image(systemName: "xmark")
                                    .resizable()
                                    .foregroundColor(Color(red: 116/255, green: 116/255, blue: 128/255))
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 10, height: 10)
                            }

                        }
                        .padding(.top, 35)
                        .padding(.trailing, 35)
                    }
                }
                Spacer()
            }
            
            // Other stuff
            VStack {
                deviceSheetTypeDescriptiveTextView
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.black)
                    .padding(.top, 50)
                
                Spacer()
                    .overlay(
                        Image(uiImage: frameIcon!)
                            .resizable()
                            .frame(width: 170, height: 170)
                    )

                let buttonEnabled = frameWithinPairingRange && deviceSheetType == .pairing

                Button {
                    if buttonEnabled {
                        _onConnectPressed?()
                        showDeviceSheet = false // dismiss view
                    }
                } label: {
                    connectionButtonTextView
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 306, height: 50)
                }
                .background(Color(red: 242/255, green: 242/255, blue: 247/255))
                .foregroundColor(buttonEnabled ? .black : Color(red: 141/255, green: 141/255, blue: 147/255))
                .cornerRadius(15)
                .disabled(!buttonEnabled)
                .padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder
    var deviceSheetTypeDescriptiveTextView: some View {
        if deviceSheetType == .pairing {
            Text("Bring your device close.")
        } else {
            Text("Updating Software \(updateProgressPercent)%")
        }
    }

    @ViewBuilder
    var connectionButtonTextView: some View {
        if deviceSheetType == .pairing {
            if frameWithinPairingRange {
                Text("Frame. Connect")
            } else {
                Text("Searching")
            }
        } else {
            Text("Keep the app open")
        }
    }

    init(showDeviceSheet: Binding<Bool>, deviceSheetType: Binding<DeviceSheetType>, frameWithinPairingRange: Binding<Bool>, updateProgressPercent: Binding<Int>, onConnectPressed: (() -> Void)?) {
        _showDeviceSheet = showDeviceSheet
        _deviceSheetType = deviceSheetType
        _frameWithinPairingRange = frameWithinPairingRange
        _updateProgressPercent = updateProgressPercent
        _onConnectPressed = onConnectPressed
    }
}


