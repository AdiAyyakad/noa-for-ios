//
//  StableDiffusion.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 8/28/23.
//

import OSLog
import UIKit

class StableDiffusion: NSObject {
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
            // Background upload tasks use a file (uploadTask() can only be called from background
            // with a file)
            tempFileURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
            fallthrough
        case .backgroundData:
            // Configure a URL session that supports background transfers
            let configuration = URLSessionConfiguration.background(withIdentifier: "StableDiffusion-\(UUID().uuidString)")
            configuration.isDiscretionary = false
            configuration.shouldUseExtendedBackgroundIdleMode = true
            configuration.sessionSendsLaunchEvents = true
            configuration.allowsConstrainedNetworkAccess = true
            configuration.allowsExpensiveNetworkAccess = true
            session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        }
    }

    public func imageToImage(image: UIImage, prompt: String, model: String, strength: Float, guidance: Int, apiKey: String, completion: @escaping (Result<UIImage, AIError>) -> Void) {
        // Stable Diffusion wants images to be multiples of 64 pixels on each side
        guard let pngImageData = getPNGData(for: image) else {
            DispatchQueue.main.async {
                completion(.failure(.dataFormatError(message: "Unable to crop image and convert to PNG")))
            }
            return
        }

        // Prepare URL request
        let boundary = UUID().uuidString
        let url = URL(string: "https://api.stability.ai/v1/generation/\(model)/image-to-image")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data;boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Noa/iOS", forHTTPHeaderField: "Stability-Client-ID")

        // Form data
        var formData = Data()

        // Form parameter "init_image"
        formData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"init_image\";filename=\"image.png\"\r\n".data(using: .utf8)!)
        formData.append("Content-Type:image/png\r\n\r\n".data(using: .utf8)!)
        formData.append(pngImageData)
        formData.append("\r\n".data(using: .utf8)!)

        // Form parameter "text_prompts"
        formData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"text_prompts[0][text]\"\r\n".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        formData.append(prompt.data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)

        // Form parameter "init_image_mode"
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"init_image_mode\"\r\n".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        formData.append("IMAGE_STRENGTH".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)

        // Form parameter "image_strength"
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"image_strength\"\r\n".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        formData.append("\(strength)".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)

        // Form parameter "cfg_scale"
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"cfg_scale\"\r\n".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        formData.append("\(guidance)".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)

        // Form parameter "samples"
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"samples\"\r\n".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        formData.append("1".data(using: .utf8)!)
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

        // Associate completion handler and a buffer with this task
        completionByTask[task.taskIdentifier] = completion
        responseDataByTask[task.taskIdentifier] = Data()

        // Begin
        task.resume()

        Logger.stableDiffusion.log("[StableDiffusion] Submitted image2image request with: model=\(model), strength=\(strength), guidance=\(guidance), prompt=\(prompt)")
    }

    /// Given a UIImage, expands it so that each side is the next integral multiple of 64 (as
    /// required by Stable Diffusion), letterboxing and centering the original content. Monocle
    /// sends images that are 640x400. Cropping them down to 640x384 produces an image
    /// that is *too small* for Stable Diffusion but bumping the size up *just* works.
    /// - Parameter for: Image to expand and obtain PNG data for.
    /// - Returns: PNG data of an expanded copy of the image or `nil` if there was an error.
    private func getPNGData(for image: UIImage) -> Data? {
        // Expand each dimension to multiple of 64 that is equal or greater than current size
        let currentWidth = Int(image.size.width)
        let currentHeight = Int(image.size.height)
        let newWidth = (currentWidth + 63) & ~63
        let newHeight = (currentHeight + 63) & ~63
        let newSize = CGSize(width: CGFloat(newWidth), height: CGFloat(newHeight))
        return image.expandImageWithLetterbox(to: newSize)?.pngData()
    }

    private func deliverImage(for taskIdentifier: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            guard let completion = completionByTask[taskIdentifier] else {
                Logger.stableDiffusion.log("[StableDiffusion] Error: Lost completion data for task \(taskIdentifier)")
                responseDataByTask.removeValue(forKey: taskIdentifier)
                return
            }

            completionByTask.removeValue(forKey: taskIdentifier)

            guard let responseData = responseDataByTask[taskIdentifier] else {
                Logger.stableDiffusion.log("[StableDiffusion] Error: Lost response data for task \(taskIdentifier)")
                return
            }

            responseDataByTask.removeValue(forKey: taskIdentifier)

            // Extract and deliver image
            let result = extractContent(from: responseData)
            completion(result)
        }
    }

    private func extractContent(from data: Data) -> Result<UIImage, AIError> {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let response = json as? [String: AnyObject] else {
                Logger.stableDiffusion.log("[StableDiffusion] Error: Unable to parse response")
                return .failure(.responsePayloadParseError)
            }
            if let errorType = response["name"] as? String {
                var errorMessage = "Stability AI request failed (\(errorType))"
                if let message = response["message"] as? String {
                    errorMessage += ": \(message)"
                }
                return .failure(.apiError(message: errorMessage))
            } else if let artifacts = response["artifacts"] as? [[String: AnyObject]],
                   artifacts.count > 0,
                   let base64String = artifacts[0]["base64"] as? String,
                   let base64Data = base64String.data(using: .utf8),
                   let imageData = Data(base64Encoded: base64Data),
                   let image = UIImage(data: imageData) {
                return .success(image)
            } else {
                Logger.stableDiffusion.log("[StableDiffusion] Error: Unable to parse response")
                return .failure(.responsePayloadParseError)
            }
        } catch {
            Logger.stableDiffusion.log("[StableDiffusion] Error: Unable to deserialize response: \(error)")
            return .failure(.responsePayloadParseError)
        }
    }
}

extension StableDiffusion: URLSessionDelegate {
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        let errorMessage = error == nil ? "unknown error" : error!.localizedDescription
        Logger.stableDiffusion.log("[StableDiffusion] URLSession became invalid: \(errorMessage)")

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
        Logger.stableDiffusion.log("[StableDiffusion] URLSession finished events")
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        Logger.stableDiffusion.log("[StableDiffusion] URLSession received challenge")
        guard let trust = challenge.protectionSpace.serverTrust else {
            Logger.stableDiffusion.log("[StableDiffusion] URLSession unable to use credential")
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

extension StableDiffusion: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome streamTask: URLSessionStreamTask) {
        Logger.stableDiffusion.log("[StableDiffusion] URLSessionDataTask became stream task")
        streamTask.resume()
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
        Logger.stableDiffusion.log("[StableDiffusion] URLSessionDataTask became download task")
        downloadTask.resume()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        Logger.stableDiffusion.log("[StableDiffusion] URLSessionDataTask received challenge")
        guard let trust = challenge.protectionSpace.serverTrust else {
            Logger.stableDiffusion.log("[StableDiffusion] URLSessionDataTask unable to use credential")

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
            Logger.stableDiffusion.log("[StableDiffusion] URLSessionDataTask redirected to \(urlString)")
        } else {
            Logger.stableDiffusion.log("[StableDiffusion] URLSessionDataTask redirected")
        }

        // New task
        let newTask = self.session.dataTask(with: request)

        // Replace completion
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let completion = completionByTask[task.taskIdentifier] {
                completionByTask[task.taskIdentifier] = nil // out with the old
                completionByTask[newTask.taskIdentifier] = completion     // in with the new
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
            Logger.stableDiffusion.log("[StableDiffusion] URLSessionDataTask failed to complete: \(error.localizedDescription)")
        } else {
            // Error == nil should indicate successful completion. Process final result.
            deliverImage(for: task.taskIdentifier)
            Logger.stableDiffusion.log("[StableDiffusion] URLSessionDataTask finished")
        }

        // If there really was no error, we should have received data, triggered the completion,
        // and removed the completion. If it's still hanging around, there must be some unknown
        // error or I am interpreting the task lifecycle incorrectly.
        DispatchQueue.main.async { [weak self] in
            guard let self, let completion = completionByTask[task.taskIdentifier] else { return }
            completion(.failure(.clientSideNetworkError(error: error)))
            completionByTask.removeValue(forKey: task.taskIdentifier)
            responseDataByTask.removeValue(forKey: task.taskIdentifier)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Assume that regardless of any error (including non-200 status code), the didCompleteWithError
        // delegate method will eventually be called and we can report the error there
        Logger.stableDiffusion.log("[StableDiffusion] URLSessionDataTask received response headers")
        guard let response = response as? HTTPURLResponse else {
            Logger.stableDiffusion.log("[StableDiffusion] URLSessionDataTask received unknown response type")
            return
        }
        Logger.stableDiffusion.log("[StableDiffusion] URLSessionDataTask received response code \(response.statusCode)")
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
    static let stableDiffusion = Logger(subsystem: "Service", category: "StableDiffusion")
}
