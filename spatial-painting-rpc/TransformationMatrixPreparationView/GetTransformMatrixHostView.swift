//
//  GetTransformMatrixHostView.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/21.
//

import SwiftUI

struct GetTransformMatrixHostView: View {
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
            
            Text("開始ボタンを押した後に、右手の人差し指で相手の右手の人差し指に触れてください")
            Text("約3秒後の位置を取得します")
            
            Button(action: {
                start()
            }){
                Text("\(matrixCount + 1)回目 開始")
            }
            .disabled(rpcModel.coordinateTransforms.requestTransform)
            
            Divider()
            Spacer()
            
            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundColor(.red)
            }
            
            Button(action: {
                returnToInitial()
            }){
                Text("設定をやめる")
            }
            
            Spacer()
        }
    }
    
    private func start() {
        let rpcResult = rpcModel.sendRequest(
            RequestSchema(
                peerId: rpcModel.mcPeerIDUUIDWrapper.mine.hash,
                method: .requestTransform,
                param: .requestTransform(.init())
            ),
            mcPeerId: rpcModel.coordinateTransforms.otherPeerId
        )
        if !rpcResult.success {
            errorMessage = rpcResult.errorMessage
        }
    }
    
    private func returnToInitial() {
        let rpcResult = rpcModel.sendRequest(
            RequestSchema(
                peerId: rpcModel.mcPeerIDUUIDWrapper.mine.hash,
                method: .resetPeer,
                param: .resetPeer(.init())
            ),
            mcPeerId: rpcModel.coordinateTransforms.otherPeerId
        )
        if !rpcResult.success {
            errorMessage = rpcResult.errorMessage
        }
    }
}
