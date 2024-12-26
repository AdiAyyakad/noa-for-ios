//
//  Whisper.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/24/23.
//
//  Background Mode Notes
//  ---------------------
//  The background configuration can successfully be launched from background mode e.g. via a
//  Bluetooth callback. Online documentation indicates a dataTask() is not allowed in background
//  mode but clearly works here. A subsequent background mode URLSession called when the first
//  completes does indeed appear to fail. Likewise, uploadTask(), which documentation states is
//  specifically intended for background mode, also fails, even when used as part of the first
//  transfer.
//
//  I do not perceive a difference using files with uploadTask().
//
//  Not sure how dataTask() with a Data buffer can work on a background queue if it is executed
//  in a separate process. But it does appear to work.
//
//  Errors appear to occur when there is some sort of a delay. For example, this log shows that
//  a ChatGPT request did not complete before another kicked off. This does not happen when the
//  app is in foreground. Somehow, multiple background requests are problematic and possibly
//  being slow-walked.
//
//    *** START 21:52:26
//    [Whisper] URLSession received challenge
//    [Whisper] URLSessionDataTask received response headers
//    [Whisper] URLSessionDataTask received response code 200
//    [Whisper] Response payload: {"text":"How fast is the CPU in my iPhone?"}
//    [Whisper] URLSessionDataTask finished
//    [ChatGPT] URLSession received challenge
//    [BluetoothManager] Received TX value!
//    [BluetoothManager] TX value UTF-8 from Monocle: f
//
//
//    *** START 21:52:41
//    [Whisper] URLSession received challenge
//    [Whisper] URLSessionDataTask received response headers
//    [Whisper] URLSessionDataTask received response code 200
//    [Whisper] Response payload: {"text":"Where do lizards sleep at night?"}
//    [Whisper] URLSessionDataTask finished
//    2023-05-24 21:52:42.937529-0700 ChatGPT for Monocle[9390:1683226] Task <107143F9-1572-4564-86F0-92A731E9BF91>.<3> finished with error [-997] Error Domain=NSURLErrorDomain Code=-997 "Lost connection to background transfer service" UserInfo={NSErrorFailingURLStringKey=https://api.openai.com/v1/chat/completions, NSErrorFailingURLKey=https://api.openai.com/v1/chat/completions, _NSURLErrorRelatedURLSessionTaskErrorKey=(
//        "BackgroundDataTask <107143F9-1572-4564-86F0-92A731E9BF91>.<3>",
//        "LocalDataTask <107143F9-1572-4564-86F0-92A731E9BF91>.<3>"
//    ), _NSURLErrorFailingURLSessionTaskErrorKey=BackgroundDataTask <107143F9-1572-4564-86F0-92A731E9BF91>.<3>, NSLocalizedDescription=Lost connection to background transfer service}
//    [ChatGPT] URLSessionDataTask failed to complete: Lost connection to background transfer service
//    *** END 21:52:42
//    [ChatGPT] URLSession received challenge
//    [ChatGPT] URLSessionDataTask received response headers
//    [ChatGPT] URLSessionDataTask received response code 200
//    [ChatGPT] Response payload: {"id":"chatcmpl-7JxFrgKumSD9JIW7p3dH5zKgAgLYX","object":"chat.completion","created":1684990363,"model":"gpt-3.5-turbo-0301","usage":{"prompt_tokens":89,"completion_tokens":24,"total_tokens":113},"choices":[{"message":{"role":"assistant","content":"A Cadbury cream egg contains approximately 150 calories, 6 grams of fat, and 20 grams of sugar."},"finish_reason":"stop","index":0}]}
//
//    *** END 21:52:47
//

import OSLog
import UIKit

class Whisper: NSObject {
    public enum NetworkConfiguration {
        case normal
        case backgroundData
        case backgroundUpload
    }

    public enum Mode {
        case transcription
        case translation
    }

    public enum AudioFormat: String {
        case wav = "wav"
        case m4a = "m4a"
    }

    private var session: URLSession!
    private var completionByTask: [Int: (Result<String, AIError>) -> Void] = [:]
    private var tempFileURL: URL?

    public init(configuration: NetworkConfiguration) {
        super.init()

        switch configuration {
        case .normal:
            session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        case .backgroundUpload:
            // Background upload tasks use a file (uploadTask() can only be called from background
            // with a file)
            tempFileURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
            fallthrough
        case .backgroundData:
            // Configure a URL session that supports background transfers
            let configuration = URLSessionConfiguration.background(withIdentifier: "Whisper-\(UUID().uuidString)")
            configuration.isDiscretionary = false
            configuration.shouldUseExtendedBackgroundIdleMode = true
            configuration.sessionSendsLaunchEvents = true
            configuration.allowsConstrainedNetworkAccess = true
            configuration.allowsExpensiveNetworkAccess = true
            session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        }
    }

    public func transcribe(mode: Mode, fileData: Data, format: AudioFormat, apiKey: String, completion: @escaping (Result<String, AIError>) -> Void) {
        let boundary = UUID().uuidString

        let function = mode == .transcription ? "transcriptions" : "translations"
        let url = URL(string: "https://api.openai.com/v1/audio/\(function)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data;boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Form data
        var formData = Data()

        // Form parameter "model"
        formData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"model\"\r\n".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        formData.append("whisper-1".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)

        if mode == .transcription {
            // Form parameter "language": en
            formData.append("--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition:form-data;name=\"language\"\r\n".data(using: .utf8)!)
            formData.append("\r\n".data(using: .utf8)!)
            formData.append("en".data(using: .utf8)!)
            formData.append("\r\n".data(using: .utf8)!)
        } else {
            // Form parameter "prompt", required to make translation work
            formData.append("--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition:form-data;name=\"prompt\"\r\n".data(using: .utf8)!)
            formData.append("\r\n".data(using: .utf8)!)
            formData.append("Translate to English".data(using: .utf8)!) // can seemingly be anything, even just "translate"
            formData.append("\r\n".data(using: .utf8)!)
        }

        // File data and form parameter "file"
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"file\";filename=\"audio.\(format.rawValue)\"\r\n".data(using: .utf8)!)  //TODO: temperature
        formData.append("Content-Type:audio/\(format.rawValue)\r\n\r\n".data(using: .utf8)!)
        formData.append(fileData)
        formData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        // If this is a background task using a file, write that file, else attach to request
        if let fileURL = tempFileURL {
            //TODO: error handling
            try? formData.write(to: fileURL)
        } else {
            request.httpBody = formData
        }

        // Create task
        let task: URLSessionDataTask = tempFileURL.flatMap(curry(session.uploadTask)(request)) ?? session.dataTask(with: request)

        // Associate completion handler with this task
        completionByTask[task.taskIdentifier] = completion

        // Begin
        task.resume()
    }
}

// MARK: - Private Helper

private extension Whisper {
    func extractContent(from data: Data) -> Result<String, AIError> {
        do {
            let jsonString = String(decoding: data, as: UTF8.self)
            if jsonString.count > 0 {
                Logger.whisper.log("[Whisper] Response payload: \(jsonString)")
            }
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let response = json as? [String: AnyObject] else {
                Logger.whisper.log("[Whisper] Error: Unable to parse response")
                return .failure(.responsePayloadParseError)
            }
            if let errorPayload = response["error"] as? [String: AnyObject],
               var errorMessage = errorPayload["message"] as? String {
                // Error from OpenAI
                if errorMessage.isEmpty {
                    // This happens sometimes, try to see if there is an error code
                    if let errorCode = errorPayload["code"] as? String,
                       !errorCode.isEmpty {
                        errorMessage = "Unable to respond. Error code: \(errorCode)"
                    } else {
                        errorMessage = "No response received. Ensure your API key is valid and try again."
                    }
                }
                return .failure(.apiError(message: errorMessage))
            } else if let text = response["text"] as? String {
                return .success(text)
            } else {
                Logger.whisper.log("[Whisper] Error: Unable to parse response")
                return .failure(.responsePayloadParseError)
            }
        } catch {
            Logger.whisper.log("[Whisper] Error: Unable to deserialize response: \(error)")
            return .failure(.responsePayloadParseError)
        }
    }
}

// MARK: - URLSessionDelegate

extension Whisper: URLSessionDelegate {
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        let errorMessage = error == nil ? "unknown error" : error!.localizedDescription
        Logger.whisper.log("[Whisper] URLSession became invalid: \(errorMessage)")

        // Deliver error for all outstanding tasks
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for (_, completion) in completionByTask {
                completion(.failure(.clientSideNetworkError(error: error)))
            }
            completionByTask = [:]
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Logger.whisper.log("[Whisper] URLSession finished events")
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        Logger.whisper.log("[Whisper] URLSession received challenge")
        guard let trust = challenge.protectionSpace.serverTrust else {
            Logger.whisper.log("[Whisper] URLSession unable to use credential")
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

// MARK: - URLSessionDataDelegate

extension Whisper: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome streamTask: URLSessionStreamTask) {
        Logger.whisper.log("[Whisper] URLSessionDataTask became stream task")
        streamTask.resume()
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
        Logger.whisper.log("[Whisper] URLSessionDataTask became download task")
        downloadTask.resume()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        Logger.whisper.log("[Whisper] URLSessionDataTask received challenge")
        guard let trust = challenge.protectionSpace.serverTrust else {
            Logger.whisper.log("[Whisper] URLSessionDataTask unable to use credential")
            DispatchQueue.main.async { [weak self] in
                self?.completionByTask.removeValue(forKey: task.taskIdentifier)?(.failure(AIError.urlAuthenticationFailed))
            }
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Original request was redirected somewhere else. Create a new task for redirection.
        if let urlString = request.url?.absoluteString {
            Logger.whisper.log("[Whisper] URLSessionDataTask redirected to \(urlString)")
        } else {
            Logger.whisper.log("[Whisper] URLSessionDataTask redirected")
        }

        // New task
        let newTask = self.session.dataTask(with: request)

        // Replace completion
        DispatchQueue.main.async { [weak self] in
            guard let self, let completion = completionByTask[task.taskIdentifier] else { return }
            completionByTask[task.taskIdentifier] = nil // out with the old
            completionByTask[newTask.taskIdentifier] = completion // in with the new
        }

        // Continue with new task
        newTask.resume()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            Logger.whisper.log("[Whisper] URLSessionDataTask failed to complete: \(error.localizedDescription)")
        } else {
            // Error == nil should indicate successful completion
            Logger.whisper.log("[Whisper] URLSessionDataTask finished")
        }

        // If there really was no error, we should have received data, triggered the completion,
        // and removed the completion. If it's still hanging around, there must be some unknown
        // error or I am interpreting the task lifecycle incorrectly.
        DispatchQueue.main.async { [weak self] in
            self?.completionByTask.removeValue(forKey: task.taskIdentifier)?(.failure(.clientSideNetworkError(error: error)))
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Assume that regardless of any error (including non-200 status code), the didCompleteWithError
        // delegate method will eventually be called and we can report the error there
        Logger.whisper.log("[Whisper] URLSessionDataTask received response headers")
        guard let response = response as? HTTPURLResponse else {
            Logger.whisper.log("[Whisper] URLSessionDataTask received unknown response type")
            return
        }
        Logger.whisper.log("[Whisper] URLSessionDataTask received response code \(response.statusCode)")
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let result = extractContent(from: data)

        // Deliver response
        DispatchQueue.main.async { [weak self] in
            self?.completionByTask.removeValue(forKey: dataTask.taskIdentifier)?(result)
        }
    }
}

extension Logger {
    static let whisper = Logger(subsystem: "Service", category: "Whisper")
}
