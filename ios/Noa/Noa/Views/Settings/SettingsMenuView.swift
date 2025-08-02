//
//  SettingsMenuView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 7/10/23.
//

import SwiftUI

struct SettingsMenuView: View {
    @EnvironmentObject private var _settings: Settings

    @Binding var showPairingView: Bool
    @Binding var bluetoothEnabled: Bool

    var body: some View {
        Menu {
            let isFramePaired = _settings.pairedDeviceID != nil

            Button(role: isFramePaired ? .destructive : .none) {
                if isFramePaired {
                    // Unpair
                    _settings.pairedDeviceID = nil
                }

                // Always return to pairing screen right after unpairing or when pairing requested
                showPairingView = true
            } label: {
                // Unpair/pair Frame
                if isFramePaired {
                    Label("Unpair Frame", systemImage: "wake")
                } else {
                    Label("Pair Frame", systemImage: "wake")
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
            showPairingView: .constant(false),
            bluetoothEnabled: .constant(true)
        )
            .environmentObject(Settings())
    }
}
