//
//  GetTransformMatrixClientView.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/21.
//

import SwiftUI

struct GetTransformMatrixClientView: View {
    @ObservedObject private var rpcModel: RPCModel
    @State private var errorMessage: String = ""
    let matrixCount: Int
    let matrixCountLimit: Int
    
    init(rpcModel: RPCModel) {
        self.rpcModel = rpcModel
        self.matrixCount = rpcModel.coordinateTransforms.matrixCount
        self.matrixCountLimit = rpcModel.coordinateTransforms.matrixCountLimit
    }
    
    var body: some View {
        VStack {
            Text("3. 右手の人差し指の位置を確認 \(matrixCount + 1) / \(matrixCountLimit)").font(.title)
            Divider()
            
            Text("相手に合わせて、右手の人差し指を合わせてください")
            
            Divider()
            Spacer()
            
            Button(action: {
                returnToInitial()
            }){
                Text("設定をやめる")
            }
            
            Spacer()
        }
    }
    
    private func returnToInitial() {
        let rpcResult = rpcModel.sendRequest(
            RequestSchema(
                peerId: rpcModel.mcPeerIDUUIDWrapper.mine.hash,
                method: .resetPeer,
                param: .resetPeer(.init())
            )
        )
        if !rpcResult.success {
            errorMessage = rpcResult.errorMessage
        }
    }
}
