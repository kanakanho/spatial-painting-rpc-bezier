//
//  MCPeerIDUUIDWrapper.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/13.
//

import MultipeerConnectivity

/// 各端末の接続状況を管理するラッパー
@Observable
class MCPeerIDUUIDWrapper {
    /// 自身の id
    var mine = MCPeerID(displayName: ProcessInfo.processInfo.hostName)
    /// 通信可能な id
    var standby: [MCPeerID] = []
    
    func remove(mcPeerID: MCPeerID) {
        standby.removeAll { $0 == mcPeerID }
    }
}
