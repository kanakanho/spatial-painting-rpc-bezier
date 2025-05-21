//
//  PeerManager.swift
//  multipeer-share-coordinate-throw-ball
//
//  Created by blueken on 2024/12/02.
//

import MultipeerConnectivity
import Combine
import ARKit

@Observable
class PeerManager: NSObject {
    private var sendExchangeDataWrapper: ExchangeDataWrapper
    private var receiveExchangeDataWrapper: ExchangeDataWrapper
    
    private var cancellable: AnyCancellable?
    
    private var mcPeerIDUUIDWrapper: MCPeerIDUUIDWrapper
    
    var isHost: Bool = false
    
    private let serviceType = "painting-rpc"
    var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser
    
    init(sendExchangeDataWrapper: ExchangeDataWrapper, receiveExchangeDataWrapper: ExchangeDataWrapper, mcPeerIDUUIDWrapper: MCPeerIDUUIDWrapper) {
        self.sendExchangeDataWrapper = sendExchangeDataWrapper
        self.receiveExchangeDataWrapper = receiveExchangeDataWrapper
        self.mcPeerIDUUIDWrapper = mcPeerIDUUIDWrapper
        
        let peerID = mcPeerIDUUIDWrapper.mine
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        
        super.init()
        
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
        
        cancellable = sendExchangeDataWrapper.$exchangeData.sink { [weak self] exchangeData in
            self?.sendExchangeDataDidChange(exchangeData)
        }
    }
    
    func sendExchangeDataDidChange(_ exchangeData: ExchangeData) {
        if exchangeData.mcPeerId != 0 {
            guard let peerID = mcPeerIDUUIDWrapper.standby.first(where: { $0.hash == exchangeData.mcPeerId }) else {
                print("Error: PeerID not found")
                return
            }
            let rpcResult =  sendRPC(exchangeData.data, to: peerID)
            if !rpcResult.success {
                print("Error sending message: \(rpcResult.errorMessage)")
            }
        } else {
            sendRPC(exchangeData.data)
        }
    }
    
    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }
    
    func firstSendMessage() {
        sendMessageForAll("Hello")
    }
    
    func sendMessageForAll(_ message: String) {
        guard !session.connectedPeers.isEmpty else {
            print("No connected peers")
            return
        }
        guard let messageData = message.data(using: .utf8) else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.session.send(messageData, toPeers: self.session.connectedPeers, with: .unreliable)
            } catch {
                print("Error sending message: \(error.localizedDescription)")
            }
        }
    }
    
    func sendRPC(_ data: Data) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.session.send(data, toPeers: self.mcPeerIDUUIDWrapper.standby, with: .unreliable)
            } catch {
                print("Error sending message: \(error.localizedDescription)")
            }
        }
    }
    
    func sendRPC(_ data: Data, to peerID: MCPeerID) -> RPCResult {
        var rpcResult = RPCResult()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.session.send(data, toPeers: [peerID], with: .unreliable)
            } catch {
                rpcResult = RPCResult("Error sending message: \(error.localizedDescription)")
            }
        }
        return rpcResult
    }
    
    func sendMessage(_ message: String) {
        guard let messageData = message.data(using: .utf8) else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.session.send(messageData, toPeers: self.mcPeerIDUUIDWrapper.standby, with: .unreliable)
                print("Send message: \(message)")
            } catch {
                print("Error sending message: \(error.localizedDescription)")
            }
        }
    }
    
    func addSendMessagePeer(uuid: UUID, peerIDHash: Int) {
        for peer in session.connectedPeers {
            if peer.hash == peerIDHash {
                mcPeerIDUUIDWrapper.standby.append(peer)
                return
            }
        }
        print("Error Not found peerID")
    }
}

extension PeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("Peer \(peerID.displayName) changed state to \(state)")
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.receiveExchangeDataWrapper.setData(data)
        }
    }
    
    // Unused delegate methods
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension PeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Failed to start advertising: \(error.localizedDescription)")
    }
}

extension PeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("Found peer: \(peerID.displayName)")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        mcPeerIDUUIDWrapper.standby.append(peerID)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("Lost peer: \(peerID.displayName)")
        mcPeerIDUUIDWrapper.remove(mcPeerID: peerID)
    }
}
