//
//  JSONRequest.swift
//  
//
//  Created by Sergii Kryvoblotskyi on 12/19/22.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class JSONRequest<ResultType> {
    
    let body: Codable?
    let url: URL
    let method: String
    
    init(body: Codable? = nil, url: URL, method: String = "POST") {
        self.body = body
        self.url = url
        self.method = method
    }
}

extension JSONRequest: URLRequestBuildable {
    
    func build(token: String, organizationIdentifier: String?, timeoutInterval: TimeInterval) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            if url.absoluteString.contains("azure.com") {
                request.setValue(token, forHTTPHeaderField: "api-key")
            } else {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            if token.starts(with: "sk-or") {
                request.setValue("https://apps.apple.com/us/app/pal-a-chatbot-client/id6447545085?platform=iphone", forHTTPHeaderField: "HTTP-Referer")
                request.setValue("Pal Chat (iOS)", forHTTPHeaderField: "X-Title")
            }
        }
        if let organizationIdentifier {
            request.setValue(organizationIdentifier, forHTTPHeaderField: "OpenAI-Organization")
        }
        request.httpMethod = method
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }
}
