//
//  Controller.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/29/23.
//

import AVFoundation
import Combine
import Foundation

class Controller {
    private let _settings: Settings
    private let _bluetooth: BluetoothManager
    private let _messages: ChatMessageStore

    private var _subscribers = Set<AnyCancellable>()

    private enum State {
        case disconnected
        case waitingForRawREPL
        case transmitingFiles
        case running
    }

    private var _state = State.disconnected
    private var _matcher: Util.StreamingStringMatcher?
    private var _filesToTransmit: [(String, String)] = []
    private var _audioData = Data()

    private let _m4aWriter = M4AWriter()
    private let _whisper = Whisper(configuration: .backgroundData)
    private let _chatGPT = ChatGPT(configuration: .backgroundData)
    private let _mockInput = MockInputGenerator()

    private var _pendingQueryByID: [UUID: String] = [:]

    init(settings: Settings, bluetooth: BluetoothManager, messages: ChatMessageStore) {
        _settings = settings
        _bluetooth = bluetooth
        _messages = messages

        // Subscribe to changed of paired device ID setting
        _settings.$pairedDeviceID.sink(receiveValue: { [weak self] (newPairedDeviceID: UUID?) in
            guard let self = self else { return }

            if let uuid = newPairedDeviceID {
                print("[Controller] Pair to \(uuid)")
            } else {
                print("[Controller] Unpair")
            }

            // Begin connection attempts or disconnect
            self._bluetooth.selectedDeviceID = newPairedDeviceID
        })
        .store(in: &_subscribers)

        // Connection to Monocle
        _bluetooth.peripheralConnected.sink { [weak self] (deviceID: UUID) in
            guard let self = self else { return }

            print("[Controller] Monocle connected")

            if self._settings.pairedDeviceID == nil {
                // We auto-connected and should save the paired device
                self._settings.setPairedDeviceID(deviceID)
            }

            transmitRawREPLCode()

            // Wait for confirmation that raw REPL was activated
            _matcher = nil
            _state = .waitingForRawREPL
        }.store(in: &_subscribers)

        // Monocle disconnected
        _bluetooth.peripheralDisconnected.sink { [weak self] in
            guard let self = self else { return }

            print("[Controller] Monocle disconnected")

            _state = .disconnected
        }.store(in: &_subscribers)

        // Data received on serial characteristic
        _bluetooth.serialDataReceived.sink { [weak self] (receivedValue: Data) in
            guard let self = self else { return }

            let str = String(decoding: receivedValue, as: UTF8.self)
            print("[Controller] Serial data from Monocle: \(str)")

            switch _state {
            case .waitingForRawREPL:
                onWaitForRawREPLState(receivedString: str)
            case .transmitingFiles:
                onTransmittingFilesState(receivedString: str)
            case .running:
                fallthrough
            default:
                break
            }
        }.store(in: &_subscribers)

        // Data received on data characteristic
        _bluetooth.dataReceived.sink { [weak self] (receivedValue: Data) in
            guard let self = self,
                  receivedValue.count >= 4,
                  _state == .running else {
                return
            }

            let command = String(decoding: receivedValue[0..<4], as: UTF8.self)
            print("[Controller] Data command from Monocle: \(command)")

            onMonocleCommand(command: command, data: receivedValue[4...])
        }.store(in: &_subscribers)
    }

    /// Submit a query from the iOS app directly.
    /// - Parameter query: Query string.
    public func submitQuery(query: String) {
        let fakeID = UUID()
        print("[Controller] Sending iOS query with transcription ID \(fakeID) to ChatGPT: \(query)")
        submitQuery(query: query, transcriptionID: fakeID)
    }

    /// Clear chat history, including ChatGPT context window.
    public func clearHistory() {
        _messages.clear()
        _chatGPT.clearHistory()
    }

    // MARK: Monocle Script Transmission

    private func onWaitForRawREPLState(receivedString str: String) {
        if _matcher == nil {
            _matcher = Util.StreamingStringMatcher(lookingFor: "raw REPL; CTRL-B to exit\r\n>")
        }

        if _matcher!.matchExists(afterAppending: str) {
            print("[Controller] Raw REPL detected")
            _matcher = nil
            _filesToTransmit = loadFilesForTransmission()
            transmitNextFile()
            _state = .transmitingFiles
        }
    }

    private func onTransmittingFilesState(receivedString str: String) {
        if _matcher == nil {
            _matcher = Util.StreamingStringMatcher(lookingFor: "OK\u{4}\u{4}>")
        }

        if _matcher!.matchExists(afterAppending: str) {
            print("[Controller] File succesfully written")
            _matcher = nil
            if _filesToTransmit.count > 0 {
                transmitNextFile()
            } else {
                print("[Controller] All files written. Starting program...")
                _bluetooth.sendSerialData(Data([ 0x04 ]))   // ^D to start app
                _state = .running
            }
        }
    }

    private func transmitRawREPLCode() {
        _bluetooth.sendSerialData(Data([ 0x03, 0x03, 0x01 ]))   // ^C (kill current), ^C (again to be sure), ^A (raw REPL mode)
    }

    private func loadFilesForTransmission() -> [(String, String)] {
        let basenames = [ "states", "graphics", "main" ]
        var files: [(String, String)] = []
        for basename in basenames {
            let filename = basename + ".py"
            let contents = loadPythonScript(named: basename)
            let escapedContents = contents.replacingOccurrences(of: "\n", with: "\\n")
            files.append((filename, escapedContents))
        }
        assert(files.count >= 1 && files.count == basenames.count)
        return files
    }

    private func loadPythonScript(named basename: String) -> String {
        let url = Bundle.main.url(forResource: basename, withExtension: "py")!
        let data = try? Data(contentsOf: url)
        guard let data = data,
              let sourceCode = String(data: data, encoding: .utf8) else {
            fatalError("Unable to load Monocle Python code from disk")
        }
        return sourceCode
    }

    private func transmitNextFile() {
        guard _filesToTransmit.count >= 1 else {
            return
        }

        let (filename, contents) = _filesToTransmit.remove(at: 0)

        // Construct file write commands
        guard let command = "f=open('\(filename)','w');f.write('''\(contents)''');f.close()".data(using: .utf8) else {
            print("[Controller] Internal error: Unable to construct file write comment")
            return
        }
        var data = Data()
        data.append(command)
        data.append(Data([ 0x04 ])) // ^D to execute the command

        // Send!
        _bluetooth.sendSerialData(data)
        print("[Controller] Sent \(filename): \(data.count) bytes")
    }

    // MARK: Monocle Commands

    private func onMonocleCommand(command: String, data: Data) {
        if command.starts(with: "ast:") {
            // Delete currently stored audio and prepare to receive new audio sample over
            // multiple packets
            print("[Controller] Received audio start command")
            _audioData.removeAll(keepingCapacity: true)
        } else if command.starts(with: "dat:") {
            // Append audio data
            print("[Controller] Received audio data packet (\(data.count) bytes)")
            _audioData.append(data)
        } else if command.starts(with: "aen:") {
            // Audio finished, submit for transcription
            print("[Controller] Received complete audio buffer (\(_audioData.count) bytes)")
            if _audioData.count.isMultiple(of: 2) {
                convertAudioToLittleEndian()
                if let pcmBuffer = AVAudioPCMBuffer.fromMonoInt16Data(_audioData, sampleRate: 16000) {
                    onVoiceReceived(voiceSample: pcmBuffer)
                } else {
                    print("[Controller] Error: Unable to convert audio data to PCM buffer")
                }
            } else {
                print("[Controller] Error: Audio buffer is not a multiple of two bytes")
            }
        } else if command.starts(with: "pon:") {
            // Transcript acknowledgment
            print("[Controller] Received pong (transcription acknowledgment)")
            let uuidStr = String(decoding: data, as: UTF8.self)
            if let uuid = UUID(uuidString: uuidStr) {
                onTranscriptionAcknowledged(id: uuid)
            }
        }
    }

    private func convertAudioToLittleEndian() {
        var idx = 0
        while (idx + 2) <= _audioData.count {
            let msb = _audioData[idx]
            _audioData[idx] = _audioData[idx + 1]
            _audioData[idx + 1] = msb
            idx += 2
        }
    }

    // MARK: User ChatGPT Query Flow

    // Step 1: Voice received from Monocle and converted to M4A
    private func onVoiceReceived(voiceSample: AVAudioPCMBuffer) {
        //guard let voiceSample = _mockInput.randomVoiceSample() else { return }

        print("[Controller] Voice received. Converting to M4A...")
        printTypingIndicatorToChat(as: .user)

        // Convert to M4A, then pass to speech transcription
        _m4aWriter.write(buffer: voiceSample) { [weak self] (fileData: Data?) in
            guard let fileData = fileData else {
                self?.printErrorToChat("Unable to process audio!", as: .user)
                return
            }
            self?.transcribe(audioFile: fileData)
        }
    }

    // Step 2: Transcribe speech to text using Whisper and send transcription UUID to Monocle
    private func transcribe(audioFile fileData: Data) {
        print("[Controller] Transcribing voice...")

        _whisper.transcribe(fileData: fileData, format: .m4a, apiKey: _settings.apiKey) { [weak self] (query: String, error: OpenAIError?) in
            guard let self = self else { return }
            if let error = error {
                printErrorToChat(error.description, as: .user)
            } else {
                // Store query and send ID to Monocle. We need to do this because we cannot perform
                // back-to-back network requests in background mode. Monocle will reply back with
                // the ID, allowing us to perform a ChatGPT request.
                let id = UUID()
                _pendingQueryByID[id] = query
                _bluetooth.sendToMonocle(transcriptionID: id)
                print("[Controller] Sent transcription ID to Monocle: \(id)")
            }
        }
    }

    // Step 3: Transcription UUID received, kick off ChatGPT request
    private func onTranscriptionAcknowledged(id: UUID) {
        // Fetch query
        guard let query = _pendingQueryByID.removeValue(forKey: id) else {
            return
        }

        print("[Controller] Sending transcript \(id) to ChatGPT as query: \(query)")

        submitQuery(query: query, transcriptionID: id)
    }

    private func submitQuery(query: String, transcriptionID id: UUID) {
        // User message
        printToChat(query, as: .user)

        // Send to ChatGPT
        printTypingIndicatorToChat(as: .chatGPT)
        _chatGPT.send(query: query, apiKey: _settings.apiKey, model: _settings.model) { [weak self] (response: String, error: OpenAIError?) in
            if let error = error {
                self?.printErrorToChat(error.description, as: .chatGPT)
            } else {
                self?.printToChat(response, as: .chatGPT)
                print("[Controller] Received response from ChatGPT for \(id): \(response)")
            }
        }
    }

    // MARK: Result Output

    private func printErrorToChat(_ message: String, as participant: Participant) {
        _messages.putMessage(Message(content: message, isError: true, participant: participant))

        // Send all error messages to Monocle
        _bluetooth.sendToMonocle(message: message, isError: true)
    }

    private func printTypingIndicatorToChat(as participant: Participant) {
        _messages.putMessage(Message(content: "", typingInProgress: true, participant: participant))
    }

    private func printToChat(_ message: String, as participant: Participant) {
        _messages.putMessage(Message(content: message, participant: participant))

        if !participant.isUser {
            // Send AI response to Monocle
            _bluetooth.sendToMonocle(message: message, isError: false)
        }
    }
}