//
//  ColorModeAdaptiveColor.swift
//  Noa
//
//  Created by Adi Ayyakad on 12/27/24.
//

import SwiftUI

struct ColorModeAdaptiveView<V: View>: View {
    @Environment(\.colorScheme) var colorScheme
    let light: () -> V
    let dark: () -> V

    var body: some View {
        if colorScheme == .light {
            light()
        } else {
            dark()
        }
    }

    init(@ViewBuilder light: @escaping () -> V, @ViewBuilder dark: @escaping () -> V) {
        self.light = light
        self.dark = dark
    }

    init(light: V, dark: V) {
        self.light = { light }
        self.dark = { dark }
    }
}

struct ColorModeAdaptiveView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ColorModeAdaptiveView(light: Color(UIColor.lightGray), dark: Color(UIColor.darkGray))
            ColorModeAdaptiveView(light: Image("BrilliantLabsLogo"), dark: Image("BrilliantLabsLogo_Dark"))
            ColorModeAdaptiveView {
                Text("Light")
            } dark: {
                Text("Dark")
            }
        }
    }
}
