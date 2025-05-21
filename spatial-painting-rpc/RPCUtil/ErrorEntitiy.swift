//
//  ErrorEntitiy.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/13.
//

import Foundation

struct ErrorEntitiy: RPCEntity {
    private let message: String
    
    init(message: String) {
        self.message = message
    }
    
    enum Method: RPCEntityMethod {
        case error
    }
    
    enum Param: RPCEntityParam {
        case error(ErrorParam)
        
        struct ErrorParam: Codable {
            let errorMessage: String
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .error(let param):
                try container.encode(param, forKey: .error)
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let param = try? container.decode(ErrorParam.self, forKey: .error) {
                self = .error(param)
            } else {
                throw DecodingError.dataCorruptedError(forKey: CodingKeys.error, in: container, debugDescription: "Invalid parameter type")
            }
        }
        
        internal enum CodingKeys: CodingKey {
            case error
        }
    }
}

typealias ErrorParam = ErrorEntitiy.Param.ErrorParam
