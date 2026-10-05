//
//  ImagesQuery.swift
//  
//
//  Created by Sergii Kryvoblotskyi on 02/04/2023.
//

import Foundation

public struct ImagesQuery: Codable {
    /// A text description of the desired image(s). The maximum length is 1000 characters.
    public let prompt: String
    /// The number of images to generate. Must be between 1 and 10.
    public let n: Int?
    /// The size of the generated images. Must be one of 256x256, 512x512, or 1024x1024.
    public let size: String?
    /// The model used for generating images.
    public let model: String?
    /// A flag indicating whether high-definition images are requested.
    public let quality: String?
    /// url or b64_json
    public let response_format: String?
    
    public let style: String?
    public let moderation: String?

    public init(prompt: String, n: Int?, size: String?, model: String?, quality: String?, style: String?, response_format: String? = nil) {
        self.prompt = prompt
        self.n = n
        self.size = size
        self.model = model
        self.quality = quality
        self.style = style
        self.response_format = response_format
        self.moderation = nil
    }
    
    public init(prompt: String, n: Int?, size: String?, response_format: String? = nil) {
        self.prompt = prompt
        self.n = n
        self.size = size
        self.model = nil
        self.quality = nil
        self.style = nil
        self.response_format = response_format
        self.moderation = nil
    }
    
    public init(prompt: String, model: String, quality: String, moderation: String) {
        self.prompt = prompt
        self.n = nil
        self.size = nil
        self.model = model
        self.quality = quality
        self.style = nil
        self.response_format = nil
        self.moderation = moderation
    }
}

