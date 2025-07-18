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
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow: OpenWindowAction
    @Environment(\.dismissWindow) private var dismissWindow: DismissWindowAction
    @Environment(\.displayScale) private var displayScale: CGFloat
    
    @State private var latestRightIndexFingerCoordinates: simd_float4x4 = .init()
    @State private var lastIndexPose: SIMD3<Float>? = nil
    @State private var sourceTransform: Transform? = nil
    @State private var isFileManagerActive: Bool = false
    
    var body: some View {
        RealityView { content in
            do {
                let scene: Entity = try await Entity(named: "colorpallet", in: realityKitContentBundle)
                
                if let eraserEntity: Entity = scene.findEntity(named: "collider") {
                    appModel.rpcModel.painting.paintingCanvas.setEraserEntity(eraserEntity)
                } else {
                    print("eraserEntity not found")
                }
                
                if let buttonEntity: Entity = scene.findEntity(named: "button") {
                    appModel.model.setButtonEntity(buttonEntity)
                } else {
                    print("buttonEntity not found")
                }
                
                if let buttonEntity2: Entity = scene.findEntity(named: "button2") {
                    appModel.model.setButtonEntity2(buttonEntity2)
                } else {
                    print("buttonEntity2 not found")
                }
                
                appModel.rpcModel.painting.advancedColorPalletModel.setSceneEntity(scene: scene)
                
                let contentEntity: Entity = appModel.model.setupContentEntity()
                content.add(contentEntity)
                
                appModel.model.initColorPalletNodel(colorPalletModel: appModel.rpcModel.painting.advancedColorPalletModel)
                content.add(appModel.rpcModel.painting.advancedColorPalletModel.colorPalletEntity)
                appModel.rpcModel.painting.advancedColorPalletModel.initEntity()
                
                let root: Entity = appModel.rpcModel.painting.paintingCanvas.root
                content.add(root)
                
                for fingerEntity in appModel.model.fingerEntities.values {
                    _ = content.subscribe(to: CollisionEvents.Began.self, on: fingerEntity, { (collisionEvent: CollisionEvents.Began) in
                        if appModel.model.colorPalletModel.colorNames().contains(collisionEvent.entityB.name) {
                            appModel.model.changeFingerColor(entity: fingerEntity, colorName: collisionEvent.entityB.name)
                            appModel.rpcModel.painting.paintingCanvas.setMaxRadius(radius: 0.01)
                            appModel.model.isEraserMode = false
                        } else if appModel.model.colorPalletModel.toolNames().contains(collisionEvent.entityB.name) {
                            _ = appModel.rpcModel.sendRequest(
                                RequestSchema(
                                    peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                                    method: .changeFingerLineWidth,
                                    param: .changeFingerLineWidth(.init(toolName: collisionEvent.entityB.name))
                                )
                            )
                            let material: SimpleMaterial = SimpleMaterial(color: appModel.rpcModel.painting.paintingCanvas.activeColor, isMetallic: false)
                            fingerEntity.components.set(ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [material]))
                            appModel.model.isEraserMode = false
                        } else if collisionEvent.entityB.name == "eraser" {
                            let material: SimpleMaterial = SimpleMaterial(color: UIColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 0.2), isMetallic: true)
                            fingerEntity.components.set(ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [material]))
                            appModel.model.resetColor()
                            appModel.model.isEraserMode = true
                            appModel.model.colorPalletModel.selectedToolName = "eraser"
                            _ = appModel.model.recordTime(isBegan: true)
                        } else if collisionEvent.entityB.components.contains(where: { (comp: Component) in comp is StrokeComponent }) {
                            if !appModel.model.isEraserMode || !appModel.rpcModel.painting.paintingCanvas.tmpStrokes.isEmpty {
                                return
                            }
                            guard let strokeComponent: StrokeComponent = collisionEvent.entityB.components[StrokeComponent.self] else { return }
                            appModel.rpcModel.painting.paintingCanvas.root.children.removeAll {
                                $0.components[StrokeComponent.self]?.uuid == strokeComponent.uuid
                            }
                            appModel.rpcModel.painting.paintingCanvas.strokes.removeAll {
                                $0.entity.components[StrokeComponent.self]?.uuid == strokeComponent.uuid
                            }
                        } else if collisionEvent.entityB.name == "button" {
                            _ = appModel.model.recordTime(isBegan: true)
                        } else if collisionEvent.entityB.name == "button2" {
                            _ = appModel.model.recordTime(isBegan: true)
                        }
                    })
                    
                    _ = content.subscribe(to: CollisionEvents.Ended.self, on: fingerEntity, { (collisionEvent: CollisionEvents.Ended) in
                        if appModel.rpcModel.painting.advancedColorPalletModel.colorNames().contains(collisionEvent.entityB.name) {
                            _ = appModel.rpcModel.sendRequest(
                                RequestSchema(
                                    peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                                    method: .setStrokeColor,
                                    param: .setStrokeColor(.init(strokeColorName: collisionEvent.entityB.name))
                                )
                            )
                        } else if collisionEvent.entityB.name == "button" {
                            if appModel.model.recordTime(isBegan: false) {
                                let externalStrokes: [ExternalStroke] = .init(strokes: appModel.rpcModel.painting.paintingCanvas.strokes, initPoint: .one)
                                appModel.externalStrokeFileWapper.writeStroke(
                                    externalStrokes: externalStrokes,
                                    displayScale: displayScale,
                                    planeNormalVector: appModel.model.planeNormalVector,
                                    planePoint: appModel.model.planePoint
                                )
                            }
                        } else if collisionEvent.entityB.name == "button2" {
                            if appModel.model.recordTime(isBegan: false) {
                                if !isFileManagerActive {
                                    DispatchQueue.main.async {
                                        openWindow(id: "ExternalStroke")
                                    }
                                } else {
                                    for (id,affineMatrix) in appModel.rpcModel.coordinateTransforms.affineMatrixs {
                                        let transformedExternalStrokes: [ExternalStroke] = appModel.rpcModel.painting.paintingCanvas.tmpStrokes.map { (stroke:Stroke) in
                                            let transformedPoints: [SIMD3<Float>] = stroke.points.map { (point: SIMD3<Float>) in
                                                let position = SIMD4<Float>(point.x, point.y, point.z, 1.0)
                                                let transformed = affineMatrix * (stroke.entity.transformMatrix(relativeTo: nil) * position)
                                                return SIMD3<Float>(transformed.x, transformed.y, transformed.z)
                                            }
                                            return ExternalStroke(points: transformedPoints, color: stroke.activeColor)
                                        }
                                        
                                        _ = appModel.rpcModel.sendRequest(
                                            RequestSchema(
                                                peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                                                method: .confirmTmpStrokes,
                                                param: .confirmTmpStrokes(
                                                    .init(externalStrokes: transformedExternalStrokes)
                                                )
                                            ),
                                            mcPeerId: id
                                        )
                                        DispatchQueue.main.async {
                                            dismissWindow(id: "ExternalStroke")
                                        }
                                    }
                                    isFileManagerActive.toggle()
                                }
                            }
                        } else if collisionEvent.entityB.name == "eraser" {
                            if appModel.model.recordTime(isBegan: false) {
                                _ = appModel.rpcModel.sendRequest(
                                    RequestSchema(
                                        peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                                        method: .removeAllStroke,
                                        param: .removeAllStroke(.init())
                                    )
                                )
                            }
                        } else if collisionEvent.entityB.components.contains(where: { (comp: Component) in comp is StrokeComponent }) {
                            if !appModel.model.isEraserMode { return }
                            guard let strokeComponent: StrokeComponent = collisionEvent.entityB.components[StrokeComponent.self] else { return }
                            print("Removing stroke with UUID: \(strokeComponent.uuid)")
                            _ = appModel.rpcModel.sendRequest(
                                RequestSchema(
                                    peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                                    method: .removeStroke,
                                    param: .removeStroke(.init(uuid: strokeComponent.uuid))
                                )
                            )
                        }
                    })
                }
                
                root.components.set(ClosureComponent(closure: { (deltaTime: TimeInterval) in
                    var anchors: [HandAnchor] = []
                    
                    if let left: HandAnchor = appModel.model.latestHandTracking.left {
                        anchors.append(left)
                    }
                    
                    if let right: HandAnchor = appModel.model.latestHandTracking.right {
                        anchors.append(right)
                    }
                    
                    for anchor in anchors {
                        guard let handSkeleton: HandSkeleton = anchor.handSkeleton else { continue }
                        
                        let thumbPos: SIMD3<Float> = (anchor.originFromAnchorTransform * handSkeleton.joint(.thumbTip).anchorFromJointTransform).position
                        let indexPos: SIMD3<Float> = (anchor.originFromAnchorTransform * handSkeleton.joint(.indexFingerTip).anchorFromJointTransform).position
                        let pinchThreshold: Float = 0.03
                        
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
        .onChange(of: appModel.model.isArrowShown) { _, newValue in
            Task {
                if newValue {
                    appModel.model.showHandArrowEntities()
                } else {
                    appModel.model.hideHandArrowEntities()
                }
            }
        }
        .onDisappear {
            appModel.model.dismissHandArrowEntities()
            appModel.model.colorPalletModel.colorPalletEntity.children.removeAll()
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .simultaneously(with: MagnifyGesture())
                .targetedToAnyEntity()
                .onChanged({ value in
                    if sourceTransform == nil {
                        sourceTransform = value.entity.transform
                    }
                    if !appModel.rpcModel.painting.paintingCanvas.tmpStrokes.isEmpty {
                        if value.entity.name == "boundingBox" {
                            let isHandGripped = appModel.model.isHandGripped
                            
                            if isHandGripped {
                                if let translation = value.first?.translation3D {
                                    let rotationX = Float(translation.x / 1000.0) * .pi
                                    let rotationY = Float(translation.y / 1000.0) * .pi
                                    
                                    //print("rotationX = \(rotationX), rotationY = \(rotationY)")
                                    value.entity.transform.rotation = sourceTransform!.rotation * simd_quatf(angle: rotationX, axis: [0, 1, 0]) * simd_quatf(angle: rotationY, axis: [1, 0, 0])
                                }
                            } else if let magnification = value.second?.magnification {
                                //print("magnification: \(magnification)")
                                let magnification = Float(magnification)
                                
                                value.entity.transform.scale = [sourceTransform!.scale.x * magnification, sourceTransform!.scale.y * magnification, sourceTransform!.scale.z * magnification]
                                
                                value.entity.children.forEach { child in
                                    appModel.rpcModel.painting.paintingCanvas.tmpStrokes.filter({ $0.entity.components[StrokeComponent.self]?.uuid == child.components[StrokeComponent.self]?.uuid }).forEach { stroke in
                                        stroke.updateMaxRadiusAndRemesh(scaleFactor: value.entity.transform.scale.sum() / 3)
                                    }
                                }
                            } else if let translation = value.first?.translation3D {
                                let convertedTranslation = value.convert(translation, from: .local, to: value.entity.parent!)
                                
                                value.entity.transform.translation = sourceTransform!.translation + convertedTranslation
                            }
                        }
                    } else if !appModel.model.isEraserMode,
                              appModel.rpcModel.coordinateTransforms.coordinateTransformEntity.state == .initial,
                              let pos = lastIndexPose {
                        let uuid: UUID = UUID()
                        appModel.rpcModel.painting.paintingCanvas.addPoint(uuid, pos)
                        let matrix:[Double] = [pos.x.toDouble(), pos.y.toDouble(), pos.z.toDouble(), 1]
                        for (id,affineMatrix) in appModel.rpcModel.coordinateTransforms.affineMatrixs {
                            let clientPos = matmul4x4_4x1(affineMatrix.doubleList, matrix)
                            _ = appModel.rpcModel.sendRequest(
                                RequestSchema(
                                    peerId: appModel.rpcModel.mcPeerIDUUIDWrapper.mine.hash,
                                    method: .addStrokePoint,
                                    param: .addStrokePoint(
                                        .init(
                                            uuid: uuid,
                                            point: .init(x: Float(clientPos[0]), y: Float(clientPos[1]), z: Float(clientPos[2]))
                                        )
                                    )
                                ),
                                mcPeerId: id
                            )
                        }
                    }
                })
                .onEnded({ _ in
                    if appModel.rpcModel.painting.paintingCanvas.tmpStrokes.isEmpty,
                       !appModel.model.isEraserMode,
                       appModel.rpcModel.coordinateTransforms.coordinateTransformEntity.state == .initial {
                        _ = appModel.rpcModel.sendRequest(
                            RequestSchema(
                                peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                                method: .finishStroke,
                                param: .finishStroke(.init())
                            )
                        )
                    }
                })
        )
        .onChange(of: appModel.rpcModel.coordinateTransforms.affineMatrixs) {
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
