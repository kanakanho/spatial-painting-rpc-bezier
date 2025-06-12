//
//  ImmersiveViewModel.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/03/18.
//

import ARKit
import RealityKit
import SwiftUI

@Observable
@MainActor
class ViewModel {
    var isCanvasEnabled: Bool = false
    var colorPaletModel: ColorPaletModel?
    
    var session = ARKitSession()
    var handTracking = HandTrackingProvider()
    var sceneReconstruction = SceneReconstructionProvider()
    var worldTracking = WorldTrackingProvider()
    
    private var meshEntities = [UUID: ModelEntity]()
    var contentEntity = Entity()
    var latestHandTracking: HandsUpdates = .init(left: nil, right: nil)
    var leftHandEntity = Entity()
    var rightHandEntity = Entity()
    
    var latestRightIndexFingerCoordinates: simd_float4x4 = .init()
    var latestLeftIndexFingerCoordinates: simd_float4x4 = .init()
    
    var latestWorldTracking: WorldAnchor = .init(originFromAnchorTransform: .init())
    
    // ここで反発係数を決定している可能性あり
    let material = PhysicsMaterialResource.generate(friction: 0.8,restitution: 0.0)
    
    struct HandsUpdates {
        var left: HandAnchor?
        var right: HandAnchor?
    }
    
    var errorState = false
    
    // ストロークを消去する時の長押し時間 added by nagao 2025/3/24
    var clearTime: Int = 0
    
    var fingerEntities: [HandAnchor.Chirality: ModelEntity] = [
        //        .left: .createFingertip(name: "L", color: UIColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 1.0)),
        .right: .createFingertip(name: "R", color: UIColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 1.0))
    ]
    
    func setupContentEntity() -> Entity {
        for entity in fingerEntities.values {
            contentEntity.addChild(entity)
        }
        
        // 位置合わせする座標を教えてくれる球体の追加
        let indexFingerTipGuideBall = ModelEntity(
            mesh: .generateSphere(radius: 0.02),
            materials: [SimpleMaterial(color: .green, isMetallic: true)],
            collisionShape: .generateSphere(radius: 0.03),
            mass: 0.0
        )
        indexFingerTipGuideBall.name = "indexFingerTipGuideBall"
        indexFingerTipGuideBall.components.set(InputTargetComponent(allowedInputTypes: .all))
        indexFingerTipGuideBall.isEnabled = false
        contentEntity.addChild(indexFingerTipGuideBall)
        
        return contentEntity
    }
    
    // 指先に球を表示 added by nagao 2025/3/22
    func showFingerTipSpheres() {
        for entity in fingerEntities.values {
            contentEntity.addChild(entity)
        }
    }
    
    func dismissFingerTipSpheres() {
        for entity in fingerEntities.values {
            entity.removeFromParent()
        }
    }
    
    // 指先の球の色を変更 added by nagao 2025/3/11
    func fingerSignal(hand: HandAnchor.Chirality, flag: Bool) {
        if flag {
            let goldColor = UIColor(red: 255/255, green: 215/255, blue: 0/255, alpha: 1.0)
            let material = SimpleMaterial(color: goldColor, isMetallic: true)
            self.fingerEntities[hand]?.components.set(ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [material]))
        } else {
            let silverColor = UIColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 1.0)
            let material = SimpleMaterial(color: silverColor, isMetallic: true)
            self.fingerEntities[hand]?.components.set(ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [material]))
        }
    }
    
    func processReconstructionUpdates() async {
        for await update in sceneReconstruction.anchorUpdates {
            let meshAnchor = update.anchor
            
            guard let shape = try? await ShapeResource.generateStaticMesh(from: meshAnchor) else { continue }
            switch update.event {
            case .added:
                let entity = ModelEntity()
                entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
                entity.collision = CollisionComponent(shapes: [shape], isStatic: true)
                entity.components.set(InputTargetComponent())
                
                // mode が dynamic でないと物理演算が適用されない
                entity.physicsBody = PhysicsBodyComponent(mode: .dynamic)
                
                meshEntities[meshAnchor.id] = entity
                contentEntity.addChild(entity)
            case .updated:
                guard let entity = meshEntities[meshAnchor.id] else { continue }
                entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
                entity.collision?.shapes = [shape]
            case .removed:
                meshEntities[meshAnchor.id]?.removeFromParent()
                meshEntities.removeValue(forKey: meshAnchor.id)
            }
        }
    }
    
    func monitorSessionEvents() async {
        for await event in session.events {
            switch event {
            case .authorizationChanged(type: _, status: let status):
                print("Authorization changed to: \(status)")
                
                if status == .denied {
                    errorState = true
                }
            case .dataProviderStateChanged(dataProviders: let providers, newState: let state, error: let error):
                print("Data provider changed: \(providers), \(state)")
                if let error {
                    print("Data provider reached an error state: \(error)")
                    errorState = true
                }
            @unknown default:
                fatalError("Unhandled new event type \(event)")
            }
        }
    }
    
    func processWorldUpdates() async {
        for await update in worldTracking.anchorUpdates {
            switch update.event {
            case .updated:
                let anchor = update.anchor
                latestWorldTracking = anchor
                print(latestWorldTracking.originFromAnchorTransform.position)
            default:
                break
            }
        }
    }
    
    func processHandUpdates() async {
        for await update in handTracking.anchorUpdates {
            switch update.event {
            case .updated:
                let anchor = update.anchor
                
                guard anchor.isTracked else { continue }
                
                // added by nagao 2025/3/22
                let fingerTipIndex = anchor.handSkeleton?.joint(.indexFingerTip)
                let originFromWrist = anchor.originFromAnchorTransform
                let wristFromIndex = fingerTipIndex?.anchorFromJointTransform
                let originFromIndex = originFromWrist * wristFromIndex!
                fingerEntities[anchor.chirality]?.setTransformMatrix(originFromIndex, relativeTo: nil)
                
                if anchor.chirality == .left {
                    latestHandTracking.left = anchor
                    guard let handAnchor = latestHandTracking.left else { continue }
                    guard let handSkeletonAnchorTransform = latestHandTracking.left?.handSkeleton?.joint(.indexFingerTip).anchorFromJointTransform else { return }
                    latestLeftIndexFingerCoordinates = handAnchor.originFromAnchorTransform * handSkeletonAnchorTransform
                    watchLeftPalm(handAnchor: handAnchor)
                } else if anchor.chirality == .right {
                    latestHandTracking.right = anchor
                    guard let handAnchor = latestHandTracking.right else { continue }
                    guard let handSkeletonAnchorTransform = latestHandTracking.right?.handSkeleton?.joint(.indexFingerTip).anchorFromJointTransform else { return }
                    latestRightIndexFingerCoordinates = handAnchor.originFromAnchorTransform * handSkeletonAnchorTransform
                }
            default:
                break
            }
        }
    }
    
    // 手のひらをどこに向けているのかを判定
    func watchLeftPalm(handAnchor: HandAnchor) {
        // 座標変換の処理が終了するまでは、お絵描きの機能を行えないようにする
        if !isCanvasEnabled {
            return
        }
        
        guard let middleFingerIntermediateBase = handAnchor.handSkeleton?.joint(.middleFingerIntermediateBase) else {
            return
        }
        
        let positionMatrix: simd_float4x4 = handAnchor.originFromAnchorTransform * middleFingerIntermediateBase.anchorFromJointTransform
        
        if (positionMatrix.codable[1][1] < positionMatrix.codable[2][2]) {
            colorPaletModel?.colorPaletEntityDisable()
            return
        }
        
        if !(colorPaletModel?.colorPaletEntity.isEnabled)! {
            colorPaletModel?.colorPaletEntityEnabled()
        }
        
        guard let wristBase = handAnchor.handSkeleton?.joint(.wrist) else {
            return
        }
        
        let wristMatrix: simd_float4x4 = handAnchor.originFromAnchorTransform * wristBase.anchorFromJointTransform
        
        colorPaletModel?.updatePosition(position: positionMatrix.position, wristPosition: wristMatrix.position)
    }
    
    func changeFingerColor(entity: Entity, colorName: String) {
        guard let colors = colorPaletModel?.colors else {
            return
        }
        for color in colors {
            let words = color.accessibilityName.split(separator: " ")
            if let name = words.last, name == colorName {
                let material = SimpleMaterial(color: color, isMetallic: true)
                entity.components.set(ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [material]))
                break
            }
        }
    }
    
    // ストロークを消去する時の長押し時間の処理 added by nagao 2025/3/24
    func recordTime(isBegan: Bool) -> Bool {
        if isBegan {
            let now = Date()
            let milliseconds = Int(now.timeIntervalSince1970 * 1000)
            let calendar = Calendar.current
            let nanoseconds = calendar.component(.nanosecond, from: now)
            let exactMilliseconds = milliseconds + (nanoseconds / 1_000_000)
            clearTime = exactMilliseconds
            //print("現在時刻: \(exactMilliseconds)")
            return true
        } else {
            if clearTime > 0 {
                let now = Date()
                let milliseconds = Int(now.timeIntervalSince1970 * 1000)
                let calendar = Calendar.current
                let nanoseconds = calendar.component(.nanosecond, from: now)
                let exactMilliseconds = milliseconds + (nanoseconds / 1_000_000)
                let time = exactMilliseconds - clearTime
                if time > 1000 {
                    clearTime = 0
                    //print("経過時間: \(time)")
                    return true
                }
            }
            return false
        }
    }
    
    func initBall(transform: simd_float4x4, ballColor: SimpleMaterial.Color) {
        let ball = ModelEntity(
            mesh: .generateSphere(radius: 0.02),
            materials: [SimpleMaterial(color: .cyan, isMetallic: true)],
            collisionShape: .generateSphere(radius: 0.05),
            mass: 0.0
        )
        ball.name = "rightIndexTip"
        ball.setPosition(transform.position, relativeTo: nil)
        ball.setOrientation(simd_quatf(transform), relativeTo: nil)
        ball.components.set(InputTargetComponent(allowedInputTypes: .all))
        
        contentEntity.addChild(ball)
        
        // zStrokeArrow
        let zStroke = ModelEntity(
            mesh: .init(shape: .generateBox(width: 0.004, height: 0.004, depth: 0.1)),
            materials: [SimpleMaterial(color: .blue, isMetallic: true)],
            collisionShape: .generateSphere(radius: 0.005),
            mass: 0.0
        )
        
        zStroke.name = "zStrokeArrow"
        zStroke.setPosition(SIMD3<Float>(0, 0, 0.05), relativeTo: ball)
        zStroke.setOrientation(simd_quatf(transform), relativeTo: nil)
        zStroke.components.set(InputTargetComponent(allowedInputTypes: .all))
        contentEntity.addChild(zStroke)
        
        // yStrokeArrow
        let yStroke = ModelEntity(
            mesh: .init(shape: .generateBox(width: 0.004, height: 0.1, depth: 0.004)),
            materials: [SimpleMaterial(color: .green, isMetallic: true)],
            collisionShape: .generateSphere(radius: 0.005),
            mass: 0.0
        )
        yStroke.name = "yStrokeArrow"
        yStroke.setPosition(SIMD3<Float>(0, 0.05, 0), relativeTo: ball)
        yStroke.setOrientation(simd_quatf(transform), relativeTo: nil)
        yStroke.components.set(InputTargetComponent(allowedInputTypes: .all))
        contentEntity.addChild(yStroke)
        
        // xStrokeArrow
        let xStroke = ModelEntity(
            mesh: .init(shape: .generateBox(width: 0.1, height: 0.004, depth: 0.004)),
            materials: [SimpleMaterial(color: .red, isMetallic: true)],
            collisionShape: .generateSphere(radius: 0.005),
            mass: 0.0
        )
        xStroke.name = "xStrokeArrow"
        xStroke.setPosition(SIMD3<Float>(0.05, 0, 0), relativeTo: ball)
        xStroke.setOrientation(simd_quatf(transform), relativeTo: nil)
        xStroke.components.set(InputTargetComponent(allowedInputTypes: .all))
        contentEntity.addChild(xStroke)
    }
    
    func initColorPaletNodel(colorPaletModel: ColorPaletModel) {
        self.colorPaletModel = colorPaletModel
    }
    
    enum enableIndexFingerTipGuideBallPosition {
        case left
        case right
        case top
    }
    
    func enableIndexFingerTipGuideBall(position: SIMD3<Float>) {
        guard let indexFingerTipGuideBall = contentEntity.findEntity(named: "indexFingerTipGuideBall") else {
            print("indexFingerTipGuideBall not found")
            return
        }
        indexFingerTipGuideBall.setPosition(position, relativeTo: nil)
        indexFingerTipGuideBall.isEnabled = true
    }
    
    func disableIndexFingerTipGuideBall() {
        guard let indexFingerTipGuideBall = contentEntity.findEntity(named: "indexFingerTipGuideBall") else {
            print("indexFingerTipGuideBall not found")
            return
        }
        indexFingerTipGuideBall.isEnabled = false
    }
}
