//
//  ExchangeData.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/13.
//

import Foundation

struct ExchangeData {
    var data: Data
    var mcPeerId: Int
}

class ExchangeDataWrapper: ObservableObject {
    @Published var exchangeData: ExchangeData
    
    init(data: Data, mcPeerId: Int) {
        self.exchangeData = ExchangeData(data: data, mcPeerId: mcPeerId)
    }
    
    init() {
        self.exchangeData = ExchangeData(data: Data(), mcPeerId: 0)
    }
    
    init(data: Data) {
        self.exchangeData = ExchangeData(data: data, mcPeerId: 0)
    }
    
    func setData(_ data: Data) {
        self.exchangeData = ExchangeData(data: data, mcPeerId: 0)
    }
    
    func setData(_ data: Data, to mcPeerId: Int) {
        self.exchangeData = ExchangeData(data: data, mcPeerId: mcPeerId)
    }
}
