//
//  M4AWriter.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/20/23.
//

import AVFoundation
import OSLog

class M4AWriter: NSObject, AVAssetWriterDelegate {
    private let temporaryDirectory: URL

    public override init() {
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        super.init()
    }

    deinit {
        //TODO: last file created is not cleaned up and should probably be cleaned up here
    }

    public func write(buffer: AVAudioPCMBuffer, completion: @escaping (Data?) -> Void) {
        guard let cmSampleBuffer = buffer.convertToCMSampleBuffer() else {
            Logger.m4aWriter.log("[M4AWriter] Error: Unable to convert PCM buffer to CMSampleBuffer")
            completion(nil)
            return
        }

        let file = getFileURL()

        guard let assetWriter = try? AVAssetWriter(outputURL: file, fileType: .m4a) else {
            Logger.m4aWriter.log("[M4AWriter] Error: Unable to create asset writer")
            completion(nil)
            return
        }

        assetWriter.shouldOptimizeForNetworkUse = true

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,     // voice transcription models want 16 KHz but AVAssetWriter can only encode 44.1 and 48KHz
            AVNumberOfChannelsKey: 1,   // we want only a single channel
            AVEncoderBitRateKey: 128000
        ]

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)

        assetWriter.add(audioInput)

        if !assetWriter.startWriting() {
            Logger.m4aWriter.log("[M4AWriter] Error: Unable to start writing: \(assetWriter.error?.localizedDescription ?? "unknown error")")
        }
        assetWriter.startSession(atSourceTime: .zero)
        audioInput.append(cmSampleBuffer)
        audioInput.markAsFinished()
        //assetWriter.endSession(atSourceTime: .zero)   //TODO: seems this is not needed?
        assetWriter.finishWriting { [weak assetWriter, weak self] in
            guard let self, let assetWriter else { return }
            let status = assetWriter.status
            switch status {
            case .completed:
                Logger.m4aWriter.log("[M4AWriter] Created m4a file successfully")
                load(file: file, completion: completion)
                delete(file: file)
            case .failed:
                Logger.m4aWriter.log("[M4AWriter] Error: Failed to create m4a file: \(assetWriter.error?.localizedDescription ?? "unknown error") \(String(describing: status))")
            case .cancelled, .unknown, .writing: fallthrough
            @unknown default:
                Logger.m4aWriter.log("[M4AWriter]: Error: Failed to create m4a file: \(String(describing: status))")
            }
        }
    }

    private func getFileURL() -> URL {
        return temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func load(file url: URL, completion: (Data?) -> Void) {
        let data = try? Data(contentsOf: url)
        completion(data)
    }

    private func delete(file url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Logger.m4aWriter.log("[M4AWriter] Error: Unable to delete temporary file: \(url)")
        }
    }
}

extension Logger {
    static let m4aWriter = Logger(subsystem: "Util", category: "M4AWriter")
}
