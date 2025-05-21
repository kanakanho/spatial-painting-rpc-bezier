//
//  InitialView.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/12.
//

import SwiftUI

struct InitialView: View {
    @ObservedObject private var rpcModel: RPCModel
    @State private var errorMessage = ""
    
    init(rpcModel: RPCModel) {
        self.rpcModel = rpcModel
    }
    
    var body: some View {
        VStack {
            Button(action: {
                initPeer()
            }) {
                Text("初期設定を開始します")
            }
            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundColor(.red)
            }
        }
    }
    
    private func initPeer() {
        // 次の画面に遷移
        let setStateRPCResult = rpcModel.coordinateTransforms.setState(param: .init(state: .selecting))
        if !setStateRPCResult.success {
            errorMessage = setStateRPCResult.errorMessage
            return
        }
    }
}
