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
        
        let setStateRPCResult = rpcModel.coordinateTransforms.setState(param: .init(state: .prepared))
        if !setStateRPCResult.success {
            errorMessage = setStateRPCResult.errorMessage
        }
    }
    
    private func returnToInitial() {
        _ = rpcModel.coordinateTransforms.resetPeer(param: .init())
    }
}
