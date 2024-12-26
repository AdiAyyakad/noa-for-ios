//
//  DallE.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 8/25/23.
//

import OSLog
import UIKit

class DallE: NSObject {
    public enum NetworkConfiguration {
        case normal
        case backgroundData
        case backgroundUpload
    }

    private var session: URLSession!
    private var completionByTask: [Int: (Result<UIImage, AIError>) -> Void] = [:]
    private var responseDataByTask: [Int: Data] = [:]
    private var tempFileURL: URL?

    public init(configuration: NetworkConfiguration) {
        super.init()

        switch configuration {
        case .normal:
            session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        case .backgroundUpload:
            // Background upload tasks use a file (uploadTask() can only be called from background with a file)
            tempFileURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
            fallthrough
        case .backgroundData:
            // Configure a URL session that supports background transfers
            let configuration = URLSessionConfiguration.background(withIdentifier: "DallE-\(UUID().uuidString)")
            configuration.isDiscretionary = false
            configuration.shouldUseExtendedBackgroundIdleMode = true
            configuration.sessionSendsLaunchEvents = true
            configuration.allowsConstrainedNetworkAccess = true
            configuration.allowsExpensiveNetworkAccess = true
            session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        }
    }

    public func renderEdit(jpegFileData: Data, maskPNGFileData: Data?, prompt: String, apiKey: String, completion: @escaping (Result<UIImage, AIError>) -> Void) {
        // Convert JPEG to PNG and, if no mask supplied, mask off entire image by clearing the
        // alpha channel so that the entire image is redrawn
        guard let pngImageData = convertJPEGToPNG(jpegFileData: jpegFileData, clearAlphaChannel: maskPNGFileData == nil) else {
            DispatchQueue.main.async {
                completion(.failure(.dataFormatError(message: "Unable to convert JPEG image to PNG data")))
            }
            return
        }

        // Prepare URL request
        let boundary = UUID().uuidString
        let url = URL(string: "https://api.openai.com/v1/images/edits")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data;boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Form data
        var formData = Data()

        // Form parameter "image" -- if mask is not supplied, alpha channel is mask (alpha=0 is
        // where image will be modified)
        formData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"image\";filename=\"image.png\"\r\n".data(using: .utf8)!)
        formData.append("Content-Type:image/png\r\n\r\n".data(using: .utf8)!)
        formData.append(pngImageData)
        formData.append("\r\n".data(using: .utf8)!)

        // Form parameter "mask"
        if let maskPNGFileData = maskPNGFileData {
            formData.append("--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition:form-data;name=\"mask\";filename=\"mask.png\"\r\n".data(using: .utf8)!)
            formData.append("Content-Type:image/png\r\n\r\n".data(using: .utf8)!)
            formData.append(maskPNGFileData)
            formData.append("\r\n".data(using: .utf8)!)
        }

        // Form parameter "prompt"
        formData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"prompt\"\r\n".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        formData.append(prompt.data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)

        // Form parameter "response_format"
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"response_format\"\r\n".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        formData.append("b64_json".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)

        // Form parameter "size"
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"size\"\r\n".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        formData.append("512x512".data(using: .utf8)!)
        formData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        // If this is a background task using a file, write that file, else attach to request
        if let fileURL = tempFileURL {
            //TODO: error handling
            try? formData.write(to: fileURL)
        } else {
            request.httpBody = formData
        }

        // Create task
        let task = tempFileURL == nil ? session.dataTask(with: request) : session.uploadTask(with: request, fromFile: tempFileURL!)

        // Associate completion handler and a buffer with this task
        completionByTask[task.taskIdentifier] = completion
        responseDataByTask[task.taskIdentifier] = Data()

        // Begin
        task.resume()
    }

    private func convertJPEGToPNG(jpegFileData: Data, clearAlphaChannel: Bool) -> Data? {
        guard
            let jpegImage = UIImage(data: jpegFileData),
            let pixelBuffer = jpegImage.toPixelBuffer()
        else {
            Logger.dalle.log("[DallE] Error: Unable to convert JPEG image data to a pixel buffer")
            return nil
        }
        if clearAlphaChannel {
            pixelBuffer.clearAlpha()
        }
        guard let maskedImage = UIImage(pixelBuffer: pixelBuffer) else {
            Logger.dalle.log("[DallE] Error: Failed to convert pixel buffer to UIImage")
            return nil
        }
        guard let pngData = maskedImage.pngData() else {
            Logger.dalle.log("[DallE] Error: Failed to produce PNG encoded image")
            return nil
        }
        return pngData
    }

    private func deliverImage(for taskIdentifier: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            guard let completion = completionByTask[taskIdentifier] else {
                Logger.dalle.log("[DallE] Error: Lost completion data for task \(taskIdentifier)")
                responseDataByTask[taskIdentifier] = nil
                return
            }

            completionByTask[taskIdentifier] = nil

            guard let responseData = responseDataByTask[taskIdentifier] else {
                Logger.dalle.log("[DallE] Error: Lost response data for task \(taskIdentifier)")
                return
            }

            responseDataByTask[taskIdentifier] = nil

            // Extract and deliver image
            completion(extractContent(from: responseData))
        }
    }

    private func extractContent(from data: Data) -> Result<UIImage, AIError> {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let response = json as? [String: AnyObject] else {
                Logger.dalle.log("[DallE] Error: Unable to parse response")
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
            } else if let dataObject = response["data"] as? [[String: String]],
                   dataObject.count > 0,
                   let base64String = dataObject[0]["b64_json"],
                   let base64Data = base64String.data(using: .utf8),
                   let imageData = Data(base64Encoded: base64Data),
                   let image = UIImage(data: imageData) {
                return .success(image)
            } else {
                Logger.dalle.log("[DallE] Error: Unable to parse response")
                return .failure(.responsePayloadParseError)
            }
        } catch {
            Logger.dalle.log("[DallE] Error: Unable to deserialize response: \(error)")
            return .failure(.responsePayloadParseError)
        }
    }
}

// MARK: - URLSessionDelegate

extension DallE: URLSessionDelegate {
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        let errorMessage = error?.localizedDescription ?? "unknown error"
        Logger.dalle.log("[DallE] URLSession became invalid: \(errorMessage)")

        // Deliver error for all outstanding tasks
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for (_, completion) in completionByTask {
                completion(.failure(.clientSideNetworkError(error: error)))
            }
            completionByTask = [:]
            responseDataByTask = [:]
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Logger.dalle.log("[DallE] URLSession finished events")
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        Logger.dalle.log("[DallE] URLSession received challenge")
        guard let trust = challenge.protectionSpace.serverTrust else {
            Logger.dalle.log("[DallE] URLSession unable to use credential")
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

// MARK: - URLSessionDataDelegate

extension DallE: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome streamTask: URLSessionStreamTask) {
        Logger.dalle.log("[DallE] URLSessionDataTask became stream task")
        streamTask.resume()
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
        Logger.dalle.log("[DallE] URLSessionDataTask became download task")
        downloadTask.resume()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        Logger.dalle.log("[DallE] URLSessionDataTask received challenge")
        guard let trust = challenge.protectionSpace.serverTrust else {
            Logger.dalle.log("[DallE] URLSessionDataTask unable to use credential")

            // Deliver error
            DispatchQueue.main.async { [weak self] in
                guard let self, let completion = completionByTask[task.taskIdentifier] else { return }
                completion(.failure(.urlAuthenticationFailed))
                completionByTask[task.taskIdentifier] = nil
                responseDataByTask[task.taskIdentifier] = nil
            }
            return
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Original request was redirected somewhere else. Create a new task for redirection.
        if let urlString = request.url?.absoluteString {
            Logger.dalle.log("[DallE] URLSessionDataTask redirected to \(urlString)")
        } else {
            Logger.dalle.log("[DallE] URLSessionDataTask redirected")
        }

        // New task
        let newTask = self.session.dataTask(with: request)

        // Replace completion
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let completion = completionByTask[task.taskIdentifier] {
                completionByTask[task.taskIdentifier] = nil // out with the old
                completionByTask[newTask.taskIdentifier] = completion // in with the new
            }
            if let data = responseDataByTask[task.taskIdentifier] {
                responseDataByTask[task.taskIdentifier] = nil
                responseDataByTask[newTask.taskIdentifier] = data
            }
        }

        // Continue with new task
        newTask.resume()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Logger.dalle.log("[DallE] URLSessionDataTask failed to complete: \(error.localizedDescription)")
        } else {
            // Error == nil should indicate successful completion. Process final result.
            deliverImage(for: task.taskIdentifier)
            Logger.dalle.log("[DallE] URLSessionDataTask finished")
        }

        // If there really was no error, we should have received data, triggered the completion,
        // and removed the completion. If it's still hanging around, there must be some unknown
        // error or I am interpreting the task lifecycle incorrectly.
        DispatchQueue.main.async { [weak self] in
            guard let self, let completion = completionByTask[task.taskIdentifier] else { return }
            completion(.failure(.clientSideNetworkError(error: error)))
            completionByTask[task.taskIdentifier] = nil
            responseDataByTask[task.taskIdentifier] = nil
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Assume that regardless of any error (including non-200 status code), the didCompleteWithError
        // delegate method will eventually be called and we can report the error there
        Logger.dalle.log("[DallE] URLSessionDataTask received response headers")
        guard let response = response as? HTTPURLResponse else {
            Logger.dalle.log("[DallE] URLSessionDataTask received unknown response type")
            return
        }
        Logger.dalle.log("[DallE] URLSessionDataTask received response code \(response.statusCode)")
        completionHandler(URLSession.ResponseDisposition.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Responses can arrive in chunks
        DispatchQueue.main.async { [weak self] in
            self?.responseDataByTask[dataTask.taskIdentifier]?.append(data)
        }
    }
}

extension Logger {
    static let dalle = Logger(subsystem: "Service", category: "DallE")
}
