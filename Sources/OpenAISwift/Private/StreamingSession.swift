//
//  StreamingSession.swift
//
//  Created by Sergii Kryvoblotskyi on 18/04/2023.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class StreamingSession<ResultType: Codable>: NSObject, Identifiable, URLSessionDelegate, URLSessionDataDelegate {
    
    enum StreamingError: Error {
        case unknownContent
        case emptyContent
    }
    
    var onReceiveContent: ((StreamingSession, ResultType) -> Void)?
    var onProcessingError: ((StreamingSession, Error) -> Void)?
    var onComplete: ((StreamingSession, Error?) -> Void)?
    
    private let streamingCompletionMarker = "[DONE]"
    private let urlRequest: URLRequest
    private lazy var urlSession: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()
    
    /// Buffer to store a potential partial JSON chunk.
    private var prevChunkBuffer = ""
    
    init(urlRequest: URLRequest) {
        self.urlRequest = urlRequest
    }
    
    func perform() {
        urlSession.dataTask(with: urlRequest).resume()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // If there's any leftover (partial) JSON in the buffer, return it as an error response.
        if !prevChunkBuffer.isEmpty {
            let errorResponse = APIErrorResponse(
                error: APIError(
                    message: "```\n\(prevChunkBuffer)\n```",
                    type: "PartialBufferError",
                    param: nil,
                    code: nil
                )
            )
            onProcessingError?(self, errorResponse)
            prevChunkBuffer = ""
        }
        onComplete?(self, error)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Convert data to string and remove any unwanted content.
        guard let rawContent = String(data: data, encoding: .utf8) else {
            onProcessingError?(self, StreamingError.unknownContent)
            return
        }
        
        let stringContent = rawContent.replacingOccurrences(of: ": OPENROUTER PROCESSING", with: "")
        let combinedContent = prevChunkBuffer + stringContent
        let jsonObjects = combinedContent
            .components(separatedBy: "data:")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // Reset the partial buffer. Any new partial JSON will be added later if needed.
        prevChunkBuffer = ""
        
        // If there are no relevant JSON objects or the first object indicates completion, do nothing.
        guard !jsonObjects.isEmpty, jsonObjects.first != streamingCompletionMarker else {
            return
        }
        
        for (index, jsonContent) in jsonObjects.enumerated() {
            if jsonContent == streamingCompletionMarker {
                continue
            }
            
            guard let jsonData = jsonContent.data(using: .utf8) else {
                print("Error: Unable to convert jsonContent to Data\nContent: \(jsonContent)")
                onProcessingError?(self, StreamingError.unknownContent)
                continue
            }
            
            do {
                // Try decoding the expected ResultType.
                let object = try JSONDecoder().decode(ResultType.self, from: jsonData)
                onReceiveContent?(self, object)
            } catch {
                // If decoding as ResultType fails, try decoding as an API error response.
                if let apiErrorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: jsonData) {
                    onProcessingError?(self, apiErrorResponse)
                } else {
                    // For the last JSON component, if it does not seem complete (e.g. missing a closing brace), store it in the buffer.
                    if index == jsonObjects.count - 1 &&
                        !jsonContent.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("}") {
                        prevChunkBuffer = "data: \(jsonContent)"
                    } else if !jsonContent.hasPrefix("{\"choices") {
                        // Log the error and report using a custom error (make sure APIErrorResponse/APIError are defined).
                        print("Error processing JSON content:\n\(jsonContent)")
                        let customError = APIErrorResponse(
                            error: APIError(message: jsonContent,
                                            type: "Error",
                                            param: nil,
                                            code: nil)
                        )
                        onProcessingError?(self, customError)
                    }
                }
            }
        }
    }
}
