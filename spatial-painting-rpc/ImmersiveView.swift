//
//  ImmersiveView.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/12.
//

import SwiftUI
import ARKit
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    @Environment(\.openWindow) var openWindow
    
    @State var latestRightIndexFingerCoordinates: simd_float4x4 = .init()
    @State var lastIndexPose: SIMD3<Float>?
    
    var body: some View {
        RealityView { content in
            do {
                let scene = try await Entity(named: "Immersive", in: realityKitContentBundle)
                appModel.rpcModel.painting.colorPaletModel.setSceneEntity(scene: scene)
                
                content.add(appModel.model.setupContentEntity())
                appModel.model.initColorPaletNodel(colorPaletModel: appModel.rpcModel.painting.colorPaletModel)
                content.add(appModel.rpcModel.painting.colorPaletModel.colorPaletEntity)
                appModel.rpcModel.painting.colorPaletModel.initEntity()
                let root = appModel.rpcModel.painting.paintingCanvas.root
                content.add(root)
                
                for fingerEntity in appModel.model.fingerEntities.values {
                    _ = content.subscribe(to: CollisionEvents.Began.self, on: fingerEntity) { collisionEvent in
                        // 座標変換の処理が終了するまでは、お絵描きの機能を行えないようにする
                        if appModel.rpcModel.coordinateTransforms.affineMatrixs.isEmpty {
                            return
                        }
                        
                        if appModel.rpcModel.painting.colorPaletModel.colorNames.contains(collisionEvent.entityB.name) {
                            appModel.model.changeFingerColor(entity: fingerEntity, colorName: collisionEvent.entityB.name)
                        } else if (collisionEvent.entityB.name == "clear") {
                            _ = appModel.model.recordTime(isBegan: true)
                        }
                    }
                    
                    _ = content.subscribe(to: CollisionEvents.Ended.self, on: fingerEntity) { collisionEvent in
                        // 座標変換の処理が終了するまでは、お絵描きの機能を行えないようにする
                        if appModel.rpcModel.coordinateTransforms.affineMatrixs.isEmpty {
                            return
                        }
                        
                        if appModel.rpcModel.painting.colorPaletModel.colorNames.contains(collisionEvent.entityB.name) {
                            _ = appModel.rpcModel.sendRequest(
                                RequestSchema(
                                    peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                                    method: .setStrokeColor,
                                    param: .setStrokeColor(
                                        .init(strokeColorName: collisionEvent.entityB.name)
                                    )
                                )
                            )
                        } else if (collisionEvent.entityB.name == "clear") {
                            if appModel.model.recordTime(isBegan: false) {
                                _ = appModel.rpcModel.sendRequest(
                                    RequestSchema(
                                        peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                                        method: .removeStroke,
                                        param: .removeAllStroke(.init())
                                    )
                                )
                            }
                        }
                    }
                }
                
                root.components.set(ClosureComponent(closure: { deltaTime in
                    var anchors = [HandAnchor]()
                    
                    if let left = appModel.model.latestHandTracking.left {
                        anchors.append(left)
                    }
                    
                    if let right = appModel.model.latestHandTracking.right {
                        anchors.append(right)
                    }
                    
                    // Loop through each anchor the app detects.
                    for anchor in anchors {
                        /// The hand skeleton that associates the anchor.
                        guard let handSkeleton = anchor.handSkeleton else {
                            continue
                        }
                        
                        /// The current position and orientation of the thumb tip.
                        let thumbPos = (
                            anchor.originFromAnchorTransform * handSkeleton.joint(.thumbTip).anchorFromJointTransform).position
                        
                        /// The current position and orientation of the index finger tip.
                        let indexPos = (anchor.originFromAnchorTransform * handSkeleton.joint(.indexFingerTip).anchorFromJointTransform).position
                        
                        /// The threshold to check if the index and thumb are close.
                        let pinchThreshold: Float = 0.03
                        
                        // Update the last index position if the distance
                        // between the thumb tip and index finger tip is
                        // less than the pinch threshold.
                        if length(thumbPos - indexPos) < pinchThreshold {
                            lastIndexPose = indexPos
                        }
                    }
                }))
                
            } catch {
                print("Error in RealityView's make: \(error)")
            }
            
        }
        .task {
            do {
                try await appModel.model.session.run([appModel.model.sceneReconstruction, appModel.model.handTracking])
            } catch {
                print("Failed to start session: \(error)")
                await dismissImmersiveSpace()
                openWindow(id: "error")
            }
        }
        .task {
            await appModel.model.processHandUpdates()
        }
        .task(priority: .low) {
            await appModel.model.processReconstructionUpdates()
        }
        .task {
            await appModel.model.monitorSessionEvents()
        }
        .task {
            await appModel.model.processWorldUpdates()
        }
        .task {
            appModel.model.showFingerTipSpheres()
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged({ _ in
                    // 座標変換の処理が終了するまでは、お絵描きの機能を行えないようにする
                    if appModel.rpcModel.coordinateTransforms.affineMatrixs.isEmpty {
                        return
                    }
                    if let pos = lastIndexPose {
                        let uuid = UUID()
                        appModel.rpcModel.painting.paintingCanvas.addPoint(uuid: uuid, pos)
                        let matrix:[Double] = [pos.x.toDouble(), pos.y.toDouble(), pos.z.toDouble(), 1]
                        for (id,affineMatrix) in appModel.rpcModel.coordinateTransforms.affineMatrixs {
                            let clientPos = matmul4x4_4x1(affineMatrix.doubleList, matrix)
                            _ = appModel.rpcModel.sendRequest(
                                RequestSchema(
                                    peerId: appModel.rpcModel.mcPeerIDUUIDWrapper.mine.hash,
                                    method: .addStrokePoint,
                                    param: .addStrokePoint(.init(
                                        uuid: uuid,
                                        point: .init(x: Float(clientPos[0]), y: Float(clientPos[1]), z: Float(clientPos[2]))
                                    ))
                                ),
                                mcPeerId: id
                            )
                        }
                    }
                })
                .onEnded({ _ in
                    // 座標変換の処理が終了するまでは、お絵描きの機能を行えないようにする
                    if appModel.rpcModel.coordinateTransforms.affineMatrixs.isEmpty {
                        return
                    }
                    
                    _ = appModel.rpcModel.sendRequest(
                        RequestSchema(
                            peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                            method: .finishStroke,
                            param: .finishStroke(.init())
                        )
                    )
                })
        )
        .onChange(of: appModel.rpcModel.coordinateTransforms.affineMatrixs) {
            if !appModel.model.isCanvasEnabled && !appModel.rpcModel.coordinateTransforms.affineMatrixs.isEmpty {
                appModel.model.isCanvasEnabled = true
            }
            
            appModel.model.resetInitBall()
            appModel.model.disableIndexFingerTipGuideBall()
        }
        .onChange(of: appModel.model.latestRightIndexFingerCoordinates) {
            if appModel.rpcModel.coordinateTransforms.requestTransform {
                latestRightIndexFingerCoordinates = appModel.model.latestRightIndexFingerCoordinates
            }
        }
        .onChange(of: appModel.rpcModel.coordinateTransforms.requestTransform){
            if appModel.rpcModel.coordinateTransforms.requestTransform {
                print("immersive coordinateTransforms")
                appModel.model.fingerSignal(hand: .right, flag: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    Task{
                        appModel.model.fingerSignal(hand: .right, flag: false)
                        let rpcResult = appModel.rpcModel.sendRequest(
                            RequestSchema(
                                peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                                method: .setTransform,
                                param: .setTransform(
                                    .init(
                                        peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                                        matrix: latestRightIndexFingerCoordinates.floatList
                                    )
                                )
                            ),
                            mcPeerId: appModel.rpcModel.coordinateTransforms.otherPeerId
                        )
                        if !rpcResult.success {
                            await dismissImmersiveSpace()
                            openWindow(id: "error")
                        }
                        appModel.model.initBall(transform: latestRightIndexFingerCoordinates, ballColor: .cyan)
                    }
                }
            }
        }
        .onChange(of: appModel.rpcModel.coordinateTransforms.matrixCount) {
            if appModel.rpcModel.coordinateTransforms.matrixCount == 0 {
                return
            }
            
            guard let nextPos = appModel.rpcModel.coordinateTransforms.getNextIndexFingerTipPosition() else {
                print("No next index finger tip position available.")
                return
            }
            appModel.model.enableIndexFingerTipGuideBall(position: nextPos)
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environmentObject(AppModel())
}
