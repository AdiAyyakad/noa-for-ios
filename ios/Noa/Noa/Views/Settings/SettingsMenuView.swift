//
//  SettingsMenuView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 7/10/23.
//

import SwiftUI

struct SettingsMenuView: View {
    @EnvironmentObject private var _settings: Settings

    @Binding var popUpApiBox: Bool
    @Binding var showPairingView: Bool
    @Binding var bluetoothEnabled: Bool
    @Binding var mode: ChatGPT.Mode

    var body: some View {
        Menu {
            let isMonoclePaired = _settings.pairedDeviceID != nil

            Button {
                popUpApiBox = true
            } label: {
                Label("Manage API Keys", systemImage: "person.circle")
            }

            Toggle(isOn: .init {
                mode == .translator
            } set: { newValue in
                mode = newValue ? .translator : .assistant
            }) {
                Label("Translate", systemImage: "globe")
            }
            .toggleStyle(.button)

            Button(role: isMonoclePaired ? .destructive : .none) {
                if isMonoclePaired {
                    // Unpair
                    _settings.pairedDeviceID = nil
                }

                // Always return to pairing screen right after unpairing or when pairing requested
                showPairingView = true
            } label: {
                // Unpair/pair Monocle
                if isMonoclePaired {
                    Label("Unpair Monocle", systemImage: "wake")
                } else {
                    Label("Pair Monocle", systemImage: "wake")
                }
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .foregroundColor(Color(red: 87/255, green: 199/255, blue: 170/255))
        }
    }
}

struct SettingsMenuView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsMenuView(
            popUpApiBox: .constant(false),
            showPairingView: .constant(false),
            bluetoothEnabled: .constant(true),
            mode: .constant(.assistant)
        )
            .environmentObject(Settings())
    }
}
