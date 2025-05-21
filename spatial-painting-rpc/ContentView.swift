//
//  ContentView.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/12.
//

import SwiftUI
import RealityKit
import RealityKitContent

enum SharedCoordinateState {
    case prepare
    case sharing
    case shared
}

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var sharedCoordinateState: SharedCoordinateState = .prepare
    
    var body: some View {
        VStack {
            NavigationStack {
                switch sharedCoordinateState {
                case .prepare:
                    VStack {
                        Spacer()
                        ToggleImmersiveSpaceButton()
                            .environmentObject(appModel)
                        Spacer()
                        Button("Start Sharing") {
                            appModel.peerManager.start()
                            print(appModel.mcPeerIDUUIDWrapper.mine.displayName)
                            appModel.peerManager.sendMessageForAll("hello")
                            sharedCoordinateState = .sharing
                        }
                        Spacer()
                    }
                case .sharing:
                    TransformationMatrixPreparationView(rpcModel: appModel.rpcModel, sharedCoordinateState: $sharedCoordinateState)
                case .shared:
                    Text("Shared Coordinate Ready")
                }
            }
            Spacer()
        }
        .padding()
        
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environmentObject(AppModel())
}
