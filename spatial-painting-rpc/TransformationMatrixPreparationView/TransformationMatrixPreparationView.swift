//
//  TransformationMatrixPreparationView.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/18.
//

import Foundation
import SwiftUI

struct TransformationMatrixPreparationView: View {
    @ObservedObject private var rpcModel: RPCModel
    @State private var errorMessage = ""
    var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State var time: String = ""
    @Binding private var sharedCoordinateState: SharedCoordinateState
    
    init(rpcModel: RPCModel, sharedCoordinateState: Binding<SharedCoordinateState>) {
        self.rpcModel = rpcModel
        self._sharedCoordinateState = sharedCoordinateState
    }
    
    var body: some View {
        VStack {
            HStack{
                Text("MyId:\(rpcModel.mcPeerIDUUIDWrapper.mine.hash)").font(.title)
                Text(time)
            }
            Divider()
            NavigationStack {
                switch rpcModel.coordinateTransforms.coordinateTransformEntity.state {
                case .initial:
                    InitialView(rpcModel: rpcModel)
                case .selecting:
                    SelectingPeerView(rpcModel: rpcModel)
                case .getTransformMatrixHost:
                    GetTransformMatrixHostView(rpcModel: rpcModel)
                case .getTransformMatrixClient:
                    GetTransformMatrixClientView(rpcModel: rpcModel)
                case .confirm:
                    ConfirmView(rpcModel: rpcModel)
                case .prepared:
                    Text(rpcModel.coordinateTransforms.coordinateTransformEntity.affineMatrixAtoB.debugDescription)
                    Button(action: {
                        let setStateRPCResult = rpcModel.coordinateTransforms.resetPeer(param: .init())
                        if !setStateRPCResult.success {
                            errorMessage = setStateRPCResult.errorMessage
                        }
                        sharedCoordinateState = .sharing
                    }){
                        Text("設定を完了しました")
                    }
                }
            }
            Spacer()
        }
        .onAppear() {
            _ = rpcModel.coordinateTransforms.initMyPeer(param: .init(peerId: rpcModel.mcPeerIDUUIDWrapper.mine.hash))
        }
        .onReceive(timer) { _ in
            self.time = "\(Date())"
        }
    }
}
