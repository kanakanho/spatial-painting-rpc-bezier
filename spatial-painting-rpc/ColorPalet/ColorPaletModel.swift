//
//  ColorPalet.swift
//  spatial-painting
//
//  Created by blueken on 2025/03/20.
//

import ARKit
import RealityKit
import SwiftUI
import AVFoundation

@MainActor
class ColorPaletModel: ObservableObject {
    @Published var colorPaletEntity = Entity()
    
    var sceneEntity: Entity? = nil
    
    private let systemSoundPlayer = SystemSoundPlayer()
    
    let radius: Float = 0.08
    let centerHeight: Float = 0.12
    
    let material = PhysicsMaterialResource.generate(friction: 0.8, restitution: 0.0)
    
    var activeColor = SimpleMaterial.Color.white
    
    let colors: [SimpleMaterial.Color] = [
        .white,
        .black,
        .brown,
        .red,
        .orange,
        .yellow,
        .green,
        .cyan,
        .blue,
        .purple
    ]
    
    // added by nagao 3/22
    let colorNames: [String] = [
        "white",
        "black",
        "brown",
        "red",
        "orange",
        "yellow",
        "green",
        "cyan",
        "blue",
        "magenta"
    ]
    
    init() {
        self.sceneEntity = nil
    }
    
    func setSceneEntity(scene: Entity) {
        sceneEntity = scene
    }
    
    func setActiveColor(color: SimpleMaterial.Color) {
        activeColor = color
    }
    
    func updatePosition(position: SIMD3<Float>, wristPosition: SIMD3<Float>) {
        // 中指と手首を結ぶベクトル
        let vector1 = simd_float3(x: position.x - wristPosition.x, y: 0, z: position.z - wristPosition.z)
        let radiansS: Float = Float.pi / 180.0 * 360.0 / Float(colors.count) * 1.0
        let radiansL: Float = Float.pi / 180.0 * 360.0 / Float(colors.count) * Float(colors.count - 1)
        let ballPositionS: SIMD3<Float> = SIMD3<Float>(radius * sin(radiansS), radius * cos(radiansS) + centerHeight, 0.0)
        let ballPositionL: SIMD3<Float> = SIMD3<Float>(radius * sin(radiansL), radius * cos(radiansL) + centerHeight, 0.0)
        // SecondballとLastballを結ぶベクトル
        let vector2 = simd_float3(x: ballPositionS.x - ballPositionL.x, y: 0, z: ballPositionS.z - ballPositionL.z)
        // 内積を使って角度の大きさを計算
        let dotProduct = simd_dot(normalize(vector1), normalize(vector2))
        let clampedDot = max(-1.0, min(1.0, dotProduct))  // [-1, 1] に制限
        let angle = acos(clampedDot) - Float.pi / 2.0 // 角度（ラジアン）
        
        for (index,color) in zip(colors.indices, colors) {
            let radians: Float = Float.pi / 180.0 * 360.0 / Float(colors.count) * Float(index)
            var ballPosition: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
            
            if index == 0 || index == Int(colors.count / 2) {
                ballPosition = position + SIMD3<Float>(radius * sin(radians), radius * cos(radians) + centerHeight, 0.0)
            } else {
                ballPosition = position + SIMD3<Float>(radius * sin(radians) * cos(angle), radius * cos(radians) + centerHeight, radius * sin(radians) * sin(angle))
            }
            
            //colorPaletEntity.findEntity(named: color.accessibilityName)?.setPosition(ballPosition, relativeTo: nil)
            let words = color.accessibilityName.split(separator: " ")
            if let name = words.last, let entity = colorPaletEntity.findEntity(named: String(name)) {
                entity.setPosition(ballPosition, relativeTo: nil)
            }
        }
        if let entity = colorPaletEntity.findEntity(named: "clear") {
            let spherePosition: SIMD3<Float> = position + SIMD3<Float>(0, centerHeight, 0)
            entity.setPosition(spherePosition, relativeTo: nil)
        }
    }
    
    func initEntity() {
        for (index,color) in zip(colors.indices, colors) {
            let deg = 360.0 / Float(colors.count) * Float(index)
            let radians: Float = Float.pi / 180.0 * deg
            //print("💥 Color accessibilityName \(index): \(color.accessibilityName)")
            createColorBall(color: color, radians: radians, radius: radius, parentPosition: colorPaletEntity.position)
        }
        if let entity = sceneEntity?.findEntity(named: "clear") {
            let position: SIMD3<Float> = SIMD3(0, centerHeight, 0)
            entity.setPosition(position, relativeTo: nil)
            colorPaletEntity.addChild(entity)
        }
    }
    
    func createColorBall(color: SimpleMaterial.Color, radians: Float, radius: Float, parentPosition: SIMD3<Float>) {
        // added by nagao 3/22
        let words = color.accessibilityName.split(separator: " ")
        if let name = words.last, let entity = sceneEntity?.findEntity(named: String(name)) {
            let position: SIMD3<Float> = SIMD3(radius * sin(radians), radius * cos(radians), 0)
            //print("💥 Created color: \(color.accessibilityName), position: \(position)")
            entity.setPosition(position, relativeTo: nil)
            colorPaletEntity.addChild(entity)
        }
    }
    
    func colorPaletEntityEnabled() {
        systemSoundPlayer.play(systemSound: .beginVideoRecording)
        
        colorPaletEntity.isEnabled = true
    }
    
    func colorPaletEntityDisable() {
        if (colorPaletEntity.isEnabled) {
            Task {
                DispatchQueue.main.async {
                    self.colorPaletEntity.isEnabled = false
                }
            }
        }
    }
}
