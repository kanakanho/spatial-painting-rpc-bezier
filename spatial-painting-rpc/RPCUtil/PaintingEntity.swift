//
//  PaintingCanvasEintity.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/21.
//

import Foundation
import RealityFoundation

@MainActor
class Painting:ObservableObject {
    @Published var paintingCanvas = PaintingCanvas()
    @Published var colorPaletModel = ColorPaletModel()
    
    /// 色を選択する
    /// - Parameter strokeColorName: 色の名前
    func setStrokeColor(param: SetStrokeColorParam) {
        for color in colorPaletModel.colors {
            let words = color.accessibilityName.split(separator: " ")
            if let name = words.last, name == param.strokeColorName {
                colorPaletModel.colorPaletEntityDisable()
                colorPaletModel.setActiveColor(color: color)
                paintingCanvas.setActiveColor(color: color)
                break
            }
        }
    }
    
    /// これまでに書いた全てのストロークを削除する
    func removeStrokeAll() {
        for stroke in paintingCanvas.strokes {
            stroke.entity.removeFromParent()
        }
        paintingCanvas.strokes.removeAll()
    }
    
    /// 特定のストロークを削除する
    func removeStroke(param: RemoveStrokeParam) {
        guard let stroke = paintingCanvas.strokes.first(where: { $0.entity.name == param.strokeId }) else {
            print("Stroke with id \(param.strokeId) not found.")
            return
        }
        stroke.entity.removeFromParent()
    }
    
    /// ストロークを描く
    /// - Parameter point: 描く座標
    func addStrokePoint(param: AddStrokePointParam) {
        paintingCanvas.addPoint(param.point)
    }
    
    /// ストロークを終了する
    func finishStroke() {
        paintingCanvas.finishStroke()
    }
}

struct PaintingEntity: RPCEntity {
    enum Method: RPCEntityMethod {
        case setStrokeColor
        case removeAllStroke
        case removeStroke
        case addStrokePoint
        case finishStroke
    }
    
    enum Param: RPCEntityParam {
        case setStrokeColor(SetStrokeColorParam)
        case removeAllStroke(RemoveAllStrokeParam)
        case removeStroke(RemoveStrokeParam)
        case addStrokePoint(AddStrokePointParam)
        case finishStroke(FinishStrokeParam)
        
        struct SetStrokeColorParam: Codable {
            let strokeColorName: String
        }
        
        struct RemoveAllStrokeParam: Codable {
        }
        
        struct RemoveStrokeParam: Codable {
            let strokeId: String
        }
        
        struct AddStrokePointParam: Codable {
            let point: SIMD3<Float>
        }
        
        struct FinishStrokeParam: Codable {
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .setStrokeColor(let param):
                try container.encode(param, forKey: .setStrokeColor)
            case .removeAllStroke(let param):
                try container.encode(param, forKey: .removeAllStroke)
            case .removeStroke(let param):
                try container.encode(param, forKey: .removeStroke)
            case .addStrokePoint(let param):
                try container.encode(param, forKey: .addStrokePoint)
            case .finishStroke(let param):
                try container.encode(param, forKey: .finishStroke)
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let param = try? container.decode(SetStrokeColorParam.self, forKey: .setStrokeColor) {
                self = .setStrokeColor(param)
            } else if let param = try? container.decode(RemoveAllStrokeParam.self, forKey: .removeAllStroke) {
                self = .removeAllStroke(param)
            } else if let param = try? container.decode(RemoveStrokeParam.self, forKey: .removeStroke) {
                self = .removeStroke(param)
            } else if let param = try? container.decode(AddStrokePointParam.self, forKey: .addStrokePoint) {
                self = .addStrokePoint(param)
            } else if let param = try? container.decode(FinishStrokeParam.self, forKey: .finishStroke) {
                self = .finishStroke(param)
            } else {
                throw DecodingError.dataCorruptedError(forKey: CodingKeys.setStrokeColor, in: container, debugDescription: "Invalid parameter type")
            }
        }
        
        internal enum CodingKeys: CodingKey {
            case setStrokeColor
            case removeAllStroke
            case removeStroke
            case addStrokePoint
            case finishStroke
        }
    }
}

typealias SetStrokeColorParam = PaintingEntity.Param.SetStrokeColorParam
typealias RemoveAllStrokeParam = PaintingEntity.Param.RemoveAllStrokeParam
typealias RemoveStrokeParam = PaintingEntity.Param.RemoveStrokeParam
typealias AddStrokePointParam = PaintingEntity.Param.AddStrokePointParam
typealias FinishStrokeParam = PaintingEntity.Param.FinishStrokeParam
