//
//  MCPeerIDUUIDWrapper.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/13.
//

import MultipeerConnectivity

/// 各端末の接続状況を管理するラッパー
class MCPeerIDUUIDWrapper: ObservableObject {
    /// 自身の id
    @Published var mine = MCPeerID(displayName: UUID().uuidString)
    /// 通信可能な id
    @Published var standby: [MCPeerID] = []
    
    func remove(mcPeerID: MCPeerID) {
        standby.removeAll { $0 == mcPeerID }
    }
}
