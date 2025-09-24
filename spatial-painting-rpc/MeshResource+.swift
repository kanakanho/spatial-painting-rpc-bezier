//
//  MeshResource+.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/08/19.
//

import UIKit
import RealityKit

// カスタム頂点構造体を定義
struct MyVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
}

extension MyVertex {
    // LowLevelMeshに頂点構造体のレイアウトを記述
    static var vertexAttributes: [LowLevelMesh.Attribute] = [
        .init(semantic: .position, format: .float3, layoutIndex: 0, offset: MemoryLayout<Self>.offset(of: \.position)!),
        .init(semantic: .normal, format: .float3, layoutIndex: 0, offset: MemoryLayout<Self>.offset(of: \.normal)!)
    ]
    
    static var vertexLayouts: [LowLevelMesh.Layout] = [
        .init(bufferIndex: 0, bufferStride: MemoryLayout<Self>.stride)
    ]
}

extension MeshResource {
    @MainActor static func generateLine(from fittedBeziers: [[SIMD3<Double>]], thickness: Float) throws -> MeshResource {
        var points: [SIMD3<Float>] = []
        let resolution = 8 // Points per segment
        
        for fitted in fittedBeziers {
            for i in 0..<resolution {
                let t: Double = Double(i) / Double(resolution)
                let point = cubicBezierPoint3D(
                    p0: fitted[0],
                    p1: fitted[1],
                    p2: fitted[2],
                    p3: fitted[3],
                    t: t
                )
                points.append(SIMD3<Float>(point))
            }
        }
        
        if let lastSegment = fittedBeziers.last {
            points.append(SIMD3<Float>(lastSegment[2]))
        }
        
        guard points.count >= 2 else {
            return MeshResource.generateCylinder(height: 0.001, radius: 0.001)
        }
        
        // --- 変更点 1: ストロークの開始点を取得 ---
        guard let firstPoint = points.first else {
            throw NSError(domain: "MeshResourceError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Points array is empty after processing."])
        }
        
        let subdivisions = 12
        let cylinderRadius = thickness
        
        let totalVertexCount = points.count * subdivisions
        let totalIndexCount = (points.count - 1) * subdivisions * 6
        
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexAttributes = MyVertex.vertexAttributes
        descriptor.vertexLayouts = MyVertex.vertexLayouts
        descriptor.indexType = .uint32
        descriptor.vertexCapacity = totalVertexCount
        descriptor.indexCapacity = totalIndexCount
        
        guard let lowLevelMesh = try? LowLevelMesh(descriptor: descriptor) else {
            throw NSError(domain: "MeshResourceError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create LowLevelMesh"])
        }
        
        var minBounds = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxBounds = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        
        lowLevelMesh.replaceUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
            let vertices = rawBytes.bindMemory(to: MyVertex.self)
            
            // 頂点プロファイル（円の断面）を計算
            let profile: [SIMD2<Float>] = (0..<subdivisions).map { j in
                let angle = 2.0 * .pi * Float(j) / Float(subdivisions)
                return SIMD2<Float>(cylinderRadius * cos(angle), cylinderRadius * sin(angle))
            }
            
            // 各サンプリング点に沿って頂点を作成
            for i in 0..<points.count {
                let currentPoint = SIMD3<Float>(points[i])
                let nextPoint = (i + 1 < points.count) ? SIMD3<Float>(points[i + 1]) : currentPoint
                let prevPoint = (i > 0) ? SIMD3<Float>(points[i-1]) : currentPoint
                
                let tangent: SIMD3<Float>
                if i == 0 {
                    tangent = simd_normalize(nextPoint - currentPoint)
                } else if i == points.count - 1 {
                    tangent = simd_normalize(currentPoint - prevPoint)
                } else {
                    tangent = simd_normalize(nextPoint - prevPoint)
                }
                
                // フレンネット・セレの標構を構築（簡略化版）
                let initialNormal = simd_cross(tangent, SIMD3<Float>(0, 1, 0))
                let normal: SIMD3<Float>
                if simd_length_squared(initialNormal) < 1e-6 {
                    // 接線がY軸と平行な場合、別の軸を使う
                    normal = simd_cross(tangent, SIMD3<Float>(0, 0, 1))
                } else {
                    normal = simd_normalize(initialNormal)
                }
                let binormal = simd_cross(tangent, normal)
                
                for j in 0..<subdivisions {
                    // 円の断面の頂点を、法線とバイノーマルを使って計算
                    let posOffset = profile[j].x * normal + profile[j].y * binormal
                    // --- 変更点 2: 頂点座標を開始点でオフセットし、ローカル座標に変換 ---
                    let pos = (currentPoint - firstPoint) + posOffset                    
                    
                    // 法線も同様に計算
                    let normalVector = simd_normalize(posOffset)
                    
                    let vertexIndex = i * subdivisions + j
                    vertices[vertexIndex] = MyVertex(position: pos, normal: normalVector)
                    
                    minBounds = simd_min(minBounds, pos)
                    maxBounds = simd_max(maxBounds, pos)
                }
            }
        }
        
        // --- インデックスデータを書き込む ---
        lowLevelMesh.replaceUnsafeMutableIndices { rawIndices in
            let indices = rawIndices.bindMemory(to: UInt32.self)
            var currentIndex = 0
            
            for i in 0..<(points.count - 1) {
                let baseIndex1 = UInt32(i * subdivisions)
                let baseIndex2 = UInt32((i + 1) * subdivisions)
                
                for j in 0..<subdivisions {
                    let jNext = (j + 1) % subdivisions
                    let i0 = baseIndex1 + UInt32(j)
                    let i1 = baseIndex2 + UInt32(j)
                    let i2 = baseIndex2 + UInt32(jNext)
                    let i3 = baseIndex1 + UInt32(jNext)
                    
                    indices[currentIndex] = i0; currentIndex += 1
                    indices[currentIndex] = i1; currentIndex += 1
                    indices[currentIndex] = i2; currentIndex += 1
                    
                    indices[currentIndex] = i0; currentIndex += 1
                    indices[currentIndex] = i2; currentIndex += 1
                    indices[currentIndex] = i3; currentIndex += 1
                }
            }
        }
        
        let meshBounds = BoundingBox(min: minBounds, max: maxBounds)
        let part = LowLevelMesh.Part(
            indexOffset: 0,
            indexCount: totalIndexCount,
            topology: .triangle,
            bounds: meshBounds
        )
        lowLevelMesh.parts.replaceAll([part])
        
        return try MeshResource(from: lowLevelMesh)
    }
}
