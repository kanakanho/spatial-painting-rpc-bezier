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
    @Environment(\.scenePhase) var scenePhase
    
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack {
            Button("File Manager") {
                openWindow(id: "ExternalStroke")
            }
            .padding(.horizontal)
            
            ToggleImmersiveSpaceButton()
                .environmentObject(appModel)
            NavigationStack {
                switch sharedCoordinateState {
                case .prepare:
                    VStack {
                        Spacer()
                        Button("Start Sharing") {
                            print(appModel.mcPeerIDUUIDWrapper.mine.displayName)
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
        .onAppear() {
            print(">>> App appeared")
            appModel.peerManager.start()
            sharedCoordinateState = .prepare
        }
        .onChange(of: scenePhase) { oldScenePhase, newScenePhase in
            if oldScenePhase == .inactive && newScenePhase == .active {
                print(">>> Scene became active")
                appModel.peerManager = PeerManager(
                    sendExchangeDataWrapper: appModel.sendExchangeDataWrapper,
                    receiveExchangeDataWrapper: appModel.receiveExchangeDataWrapper,
                    mcPeerIDUUIDWrapper: appModel.mcPeerIDUUIDWrapper
                )
                appModel.peerManager.start()
            }
            if newScenePhase == .background {
                print("<<< Scene went to background")
                sharedCoordinateState = .prepare
                appModel.mcPeerIDUUIDWrapper.standby.removeAll()
                appModel.peerManager.stop()
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environmentObject(AppModel())
}
