//
//  ConfirmView.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/18.
//

import SwiftUI

struct ConfirmView: View {
    @ObservedObject private var rpcModel: RPCModel
    @State private var errorMessage = ""
    
    init(rpcModel: RPCModel) {
        self.rpcModel = rpcModel
    }
    
    var body: some View {
        VStack {
            Text("A").font(.title)
            ForEach(0..<rpcModel.coordinateTransforms.coordinateTransformEntity.A.count, id: \.self) { index in
                Text(rpcModel.coordinateTransforms.coordinateTransformEntity.A[index].description)
            }
            
            Text("B").font(.title)
            ForEach(0..<rpcModel.coordinateTransforms.coordinateTransformEntity.B.count, id: \.self) { index in
                Text(rpcModel.coordinateTransforms.coordinateTransformEntity.B[index].description)
            }
            
            Button(action: {
                prepared()
            }){
                Text("設定を完了する")
            }
            
            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundColor(.red)
                Button(action: {
                    returnToInitial()
                }){
                    Text("設定をやめる")
                }
            }
        }
    }
    
    private func prepared() {
        let clacAffineMatrixAtoBRPCResult = rpcModel.coordinateTransforms.clacAffineMatrix(param: .init())
        if !clacAffineMatrixAtoBRPCResult.success {
            errorMessage = clacAffineMatrixAtoBRPCResult.errorMessage
            return
        }
        
        rpcModel.coordinateTransforms.setAffineMatrix()
        
        for tmpNewUserAffineMatrixs in rpcModel.coordinateTransforms.tmpNewUserAffineMatrixs {
            // 新しいユーザに既存ユーザの座標系に変換するアフィン行列を与える
            let newUserToAlreadyUserRpcResult = rpcModel.sendRequest(
                RequestSchema(
                    peerId: rpcModel.mcPeerIDUUIDWrapper.mine.hash,
                    method: .setNewUserAffineMatrix,
                    param: .setNewUserAffineMatrix(
                        .init(
                            newPeerId: tmpNewUserAffineMatrixs.newPeerId,
                            affineMatrix: tmpNewUserAffineMatrixs.newUserToAlreadyUserAffineMatrix.floatList
                        )
                    )
                ),
                mcPeerId: tmpNewUserAffineMatrixs.newPeerId
            )
            if !newUserToAlreadyUserRpcResult.success {
                errorMessage = newUserToAlreadyUserRpcResult.errorMessage
            }
            
            // 既存ユーザに新しいユーザの座標系に変換するアフィン行列を与える
            let alreadyUserTonewUserRpcResult = rpcModel.sendRequest(
                RequestSchema(
                    peerId: rpcModel.mcPeerIDUUIDWrapper.mine.hash,
                    method: .setNewUserAffineMatrix,
                    param: .setNewUserAffineMatrix(
                        .init(
                            newPeerId: tmpNewUserAffineMatrixs.alreadyPeerId,
                            affineMatrix: tmpNewUserAffineMatrixs.alreadyUserToNewUserAffineMatrix.floatList
                        )
                    )
                ),
                mcPeerId: tmpNewUserAffineMatrixs.alreadyPeerId
            )
            if !alreadyUserTonewUserRpcResult.success {
                errorMessage = newUserToAlreadyUserRpcResult.errorMessage
            }
        }
        
        let setStateRPCResult = rpcModel.coordinateTransforms.setState(param: .init(state: .prepared))
        if !setStateRPCResult.success {
            errorMessage = setStateRPCResult.errorMessage
        }
    }
    
    private func returnToInitial() {
        _ = rpcModel.coordinateTransforms.resetPeer(param: .init())
    }
}
