//
//  MessageView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/1/23.
//

import SwiftUI

struct MessageView: View {
    private let _currentMessage: Message
    @Binding private var _expandedPicture: UIImage?

    var body: some View {
        VStack {
            if let picture = _currentMessage.picture {
                HStack(alignment: .bottom, spacing: 15) {
                    leftSpacer

                    Image(uiImage: picture)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 300, maxHeight: 300, alignment: .bottomTrailing)
                        .padding(8)
                        .onTapGesture {
                            _expandedPicture = picture
                        }

                    rightSpacer
                }
            }
            if _currentMessage.text.count > 0 {
                HStack(alignment: .bottom, spacing: 15) {
                    leftSpacer

                    MessageContentView(message: _currentMessage)

                    rightSpacer
                }
            }
       }
    }

    @ViewBuilder
    var leftSpacer: some View {
        if _currentMessage.participant != .assistant {
            // User bubble pushed all the way to right, translator will be centered
            Spacer()
        }
    }

    @ViewBuilder
    var rightSpacer: some View {
        if _currentMessage.participant != .user {
            Spacer()
        }
    }

    public init(currentMessage: Message, expandedPicture: Binding<UIImage?>) {
        _currentMessage = currentMessage
        __expandedPicture = expandedPicture
    }
}

struct MessageView_Previews: PreviewProvider {
    private static var _message: Message = {
        let imageURL = Bundle.main.url(forResource: "Tahoe", withExtension: "jpg")!
        let imageData = try! Data(contentsOf: imageURL)
        let image = UIImage(data: imageData)
        return Message(text: "Lake Tahoe!", picture: image, participant: Participant.assistant)
    }()

    static var previews: some View {
        MessageView(currentMessage: Self._message, expandedPicture: .constant(nil))

    }
}
