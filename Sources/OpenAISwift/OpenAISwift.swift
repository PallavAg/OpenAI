//
//  OpenAI.swift
//
//
//  Created by Sergii Kryvoblotskyi on 9/18/22.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final public class OpenAI: OpenAIProtocol {

    public struct Configuration {
        
        /// OpenAI API token. See https://platform.openai.com/docs/api-reference/authentication
        public let token: String
        
        /// Optional OpenAI organization identifier. See https://platform.openai.com/docs/api-reference/authentication
        public let organizationIdentifier: String?
        
        /// Default request timeout
        public let timeoutInterval: TimeInterval
        
        /// API host. Set this property if you use some kind of proxy or your own server. Default is api.openai.com
        public let host: String
        
        /// Full custom URL
        public let fullEndpoint: String
        
        public init(token: String, organizationIdentifier: String? = nil, timeoutInterval: TimeInterval = 600.0, host: String, fullEndpoint: String) {
            self.token = token
            self.organizationIdentifier = organizationIdentifier
            self.host = host.isEmpty ? "api.openai.com" : host
            self.timeoutInterval = timeoutInterval
            self.fullEndpoint = fullEndpoint
        }
    }
    
    private let session: URLSessionProtocol
    private var streamingSessions: [NSObject] = []
    
    public let configuration: Configuration

    public convenience init(apiToken: String, host: String, fullEndpoint: String) {
        self.init(configuration: Configuration(token: apiToken, host: host, fullEndpoint: fullEndpoint), session: URLSession.shared)
    }
    
    public convenience init(configuration: Configuration) {
        self.init(configuration: configuration, session: URLSession.shared)
    }

    init(configuration: Configuration, session: URLSessionProtocol) {
        self.configuration = configuration
        self.session = session
    }

    public convenience init(configuration: Configuration, session: URLSession = URLSession.shared) {
        self.init(configuration: configuration, session: session as URLSessionProtocol)
    }
    
    public func completions(query: CompletionsQuery, completion: @escaping (Result<CompletionsResult, Error>) -> Void) {
        performRequest(request: JSONRequest<CompletionsResult>(body: query, url: buildURL(path: .completions)), completion: completion)
    }
    
    public func completionsStream(query: CompletionsQuery, onResult: @escaping (Result<CompletionsResult, Error>) -> Void, completion: ((Error?) -> Void)?) {
        performSteamingRequest(request: JSONRequest<CompletionsResult>(body: query.makeStreamable(), url: buildURL(path: .completions)), onResult: onResult, completion: completion)
    }
    
    public func images(query: ImagesQuery, completion: @escaping (Result<ImagesResult, Error>) -> Void) {
        performRequest(request: JSONRequest<ImagesResult>(body: query, url: buildURL(path: .images)), completion: completion)
    }
    
    public func embeddings(query: EmbeddingsQuery, completion: @escaping (Result<EmbeddingsResult, Error>) -> Void) {
        performRequest(request: JSONRequest<EmbeddingsResult>(body: query, url: buildURL(path: .embeddings)), completion: completion)
    }
    
    public func chats(query: ChatQuery, completion: @escaping (Result<ChatResult, Error>) -> Void) {
        performRequest(request: JSONRequest<ChatResult>(body: query, url: buildURL(path: .chats)), completion: completion)
    }
    
    public func chatsStream(query: ChatQuery, onResult: @escaping (Result<ChatStreamResult, Error>) -> Void, completion: ((Error?) -> Void)?) {
        performSteamingRequest(request: JSONRequest<ChatResult>(body: query.makeStreamable(), url: buildURL(path: .chats)), onResult: onResult, completion: completion)
    }
    
    public func edits(query: EditsQuery, completion: @escaping (Result<EditsResult, Error>) -> Void) {
        performRequest(request: JSONRequest<EditsResult>(body: query, url: buildURL(path: .edits)), completion: completion)
    }
    
    public func model(query: ModelQuery, completion: @escaping (Result<ModelResult, Error>) -> Void) {
        performRequest(request: JSONRequest<ModelResult>(url: buildURL(path: .models.withPath(query.model)), method: "GET"), completion: completion)
    }
    
    public func models(completion: @escaping (Result<ModelsResult, Error>) -> Void) {
        performRequest(request: JSONRequest<ModelsResult>(url: buildURL(path: .models), method: "GET"), completion: completion)
    }
    
    public func moderations(query: ModerationsQuery, completion: @escaping (Result<ModerationsResult, Error>) -> Void) {
        performRequest(request: JSONRequest<ModerationsResult>(body: query, url: buildURL(path: .moderations)), completion: completion)
    }
    
    public func audioTranscriptions(query: AudioTranscriptionQuery, completion: @escaping (Result<AudioTranscriptionResult, Error>) -> Void) {
        performRequest(request: MultipartFormDataRequest<AudioTranscriptionResult>(body: query, url: buildURL(path: .audioTranscriptions)), completion: completion)
    }
    
    public func audioTranslations(query: AudioTranslationQuery, completion: @escaping (Result<AudioTranslationResult, Error>) -> Void) {
        performRequest(request: MultipartFormDataRequest<AudioTranslationResult>(body: query, url: buildURL(path: .audioTranslations)), completion: completion)
    }
}

extension OpenAI {

    // Define a custom error type to wrap the response data as a string
    struct DataStringError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    
    func performRequest<ResultType: Codable>(request: any URLRequestBuildable, completion: @escaping (Result<ResultType, Error>) -> Void) {
        do {
            let request = try request.build(token: configuration.token, organizationIdentifier: configuration.organizationIdentifier, timeoutInterval: configuration.timeoutInterval)
            let task = session.dataTask(with: request) { data, _, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data else {
                    completion(.failure(OpenAIError.emptyData))
                    return
                }

                var apiError: Error? = nil
                do {
                    // print(String(data: data, encoding: .utf8) ?? "Unable to decode data to string")
                    let decoded = try JSONDecoder().decode(ResultType.self, from: data)
                    completion(.success(decoded))
                } catch {
                    print("ERROR: \(error)")
                    apiError = error
                }

                if apiError != nil {
                    do {
                        let decoded = try JSONDecoder().decode(APIErrorResponse.self, from: data)
                        completion(.failure(decoded))
                    } catch {
                        // Return the response data as a string inside a custom error
                        let dataString = String(data: data, encoding: .utf8) ?? "Unable to decode data to string"
                        completion(.failure(DataStringError(message: "```\n\(dataString)\n```")))
                    }
                }
            }
            task.resume()
        } catch {
            completion(.failure(error))
        }
    }
    
    func performSteamingRequest<ResultType: Codable>(request: any URLRequestBuildable, onResult: @escaping (Result<ResultType, Error>) -> Void, completion: ((Error?) -> Void)?) {
        do {
            let request = try request.build(token: configuration.token, organizationIdentifier: configuration.organizationIdentifier, timeoutInterval: configuration.timeoutInterval)
            let session = StreamingSession<ResultType>(urlRequest: request)
            session.onReceiveContent = {_, object in
                onResult(.success(object))
            }
            session.onProcessingError = {_, error in
                onResult(.failure(error))
            }
            session.onComplete = { [weak self] object, error in
                self?.streamingSessions.removeAll(where: { $0 == object })
                completion?(error)
            }
            session.perform()
            streamingSessions.append(session)
        } catch {
            completion?(error)
        }
    }
}

extension OpenAI {
    
    func buildURL(path: String) -> URL {
        guard let url = OpenAIEndpointResolver.resolve(
            hostOrBaseURL: configuration.host,
            fullEndpoint: configuration.fullEndpoint,
            requestedPath: path
        ) else {
            // URLSession reports an unsupported URL instead of crashing on malformed user input.
            return URL(fileURLWithPath: "/invalid-openai-endpoint")
        }

        print("Sending to URL: \(url)")
        return url
    }

}

enum OpenAIEndpointResolver {
    static func resolve(hostOrBaseURL: String, fullEndpoint: String, requestedPath: String) -> URL? {
        let endpoint = fullEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !endpoint.isEmpty {
            return components(for: endpoint)?.url
        }

        let baseURL = hostOrBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = components(for: baseURL),
              let hostname = components.host?.lowercased(),
              !hostname.isEmpty else {
            return nil
        }

        let basePath = normalizedPath(components.path)
        let endpointPath: String
        if basePath.isEmpty {
            endpointPath = providerSpecificPath(for: hostname, requestedPath: requestedPath)
        } else {
            endpointPath = requestedPath
        }
        components.path = appending(endpointPath, to: basePath)
        return components.url
    }

    private static func components(for address: String) -> URLComponents? {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }
        if address.contains("://") {
            return URLComponents(string: address)
        }

        return URLComponents(string: "\(defaultScheme(for: address))://\(address)")
    }

    private static func defaultScheme(for address: String) -> String {
        guard let hostname = URLComponents(string: "scheme://\(address)")?.host else {
            return "https"
        }
        return isLocalNetworkHost(hostname) ? "http" : "https"
    }

    private static func isLocalNetworkHost(_ hostname: String) -> Bool {
        let hostname = hostname.lowercased()
        if hostname == "localhost" || hostname.hasSuffix(".localhost") || hostname.hasSuffix(".local") {
            return true
        }

        if hostname == "::1" || hostname.hasPrefix("fc") || hostname.hasPrefix("fd") || hostname.hasPrefix("fe8") || hostname.hasPrefix("fe9") || hostname.hasPrefix("fea") || hostname.hasPrefix("feb") {
            return true
        }

        let octets = hostname.split(separator: ".").compactMap { Int($0) }
        if octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) {
            return octets[0] == 10 ||
            octets[0] == 127 ||
            (octets[0] == 169 && octets[1] == 254) ||
            (octets[0] == 172 && (16...31).contains(octets[1])) ||
            (octets[0] == 192 && octets[1] == 168)
        }

        return !hostname.contains(".")
    }

    private static func providerSpecificPath(for hostname: String, requestedPath: String) -> String {
        switch hostname {
        case "openrouter.ai":
            return "/api\(normalizedPath(requestedPath))"
        case "api.perplexity.ai":
            return "/chat/completions"
        case "api.groq.com":
            return "/openai\(normalizedPath(requestedPath))"
        case "text.pollinations.ai":
            return "/openai"
        default:
            return requestedPath
        }
    }

    private static func appending(_ requestedPath: String, to basePath: String) -> String {
        let basePath = normalizedPath(basePath)
        let requestedPath = normalizedPath(requestedPath)
        guard !basePath.isEmpty else { return requestedPath }
        guard !requestedPath.isEmpty else { return basePath }

        if basePath == requestedPath || basePath.hasSuffix(requestedPath) {
            return basePath
        }

        if requestedPath.hasPrefix("/v1/"), basePath == "/v1" || basePath.hasSuffix("/v1") {
            return basePath + String(requestedPath.dropFirst(3))
        }

        return basePath + requestedPath
    }

    private static func normalizedPath(_ path: String) -> String {
        guard !path.isEmpty && path != "/" else { return "" }
        var path = path.hasPrefix("/") ? path : "/\(path)"
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}

typealias APIPath = String
extension APIPath {
    
    static let completions = "/v1/completions"
    static let images = "/v1/images/generations"
    static let embeddings = "/v1/embeddings"
    static let chats = "/v1/chat/completions"
    static let edits = "/v1/edits"
    static let models = "/v1/models"
    static let moderations = "/v1/moderations"
    
    static let audioTranscriptions = "/v1/audio/transcriptions"
    static let audioTranslations = "/v1/audio/translations"
    
    func withPath(_ path: String) -> String {
        self + "/" + path
    }
}
