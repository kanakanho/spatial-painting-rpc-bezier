//
//  AppModel.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/12.
//

import SwiftUI

/// Maintains app-wide state
@MainActor
class AppModel: ObservableObject {
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    @Published var immersiveSpaceState = ImmersiveSpaceState.closed
    
    var model = ViewModel()
    
    @Published var sendExchangeDataWrapper = ExchangeDataWrapper()
    @Published var receiveExchangeDataWrapper = ExchangeDataWrapper()
    @Published var mcPeerIDUUIDWrapper = MCPeerIDUUIDWrapper()
    @ObservedObject var rpcModel: RPCModel
    var peerManager: PeerManager
    
    init() {
        let sendExchangeDataWrapper = ExchangeDataWrapper()
        let receiveExchangeDataWrapper = ExchangeDataWrapper()
        let mcPeerIDUUIDWrapper = MCPeerIDUUIDWrapper()
        
        let rpcModel = RPCModel(sendExchangeDataWrapper: sendExchangeDataWrapper, receiveExchangeDataWrapper: receiveExchangeDataWrapper, mcPeerIDUUIDWrapper: mcPeerIDUUIDWrapper)
        
        self.sendExchangeDataWrapper = sendExchangeDataWrapper
        self.receiveExchangeDataWrapper = receiveExchangeDataWrapper
        self.mcPeerIDUUIDWrapper = mcPeerIDUUIDWrapper
        
        self.rpcModel = rpcModel
        self.peerManager = PeerManager(
            sendExchangeDataWrapper: sendExchangeDataWrapper,
            receiveExchangeDataWrapper: receiveExchangeDataWrapper,
            mcPeerIDUUIDWrapper: mcPeerIDUUIDWrapper
        )
//        self.model = ViewModel()
    }
}
