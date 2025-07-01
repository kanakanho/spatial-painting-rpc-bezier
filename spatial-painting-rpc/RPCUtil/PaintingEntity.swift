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
    @Published var colorPalletModel = ColorPalletModel()
    
    /// 色を選択する
    /// - Parameter strokeColorName: 色の名前
    func setStrokeColor(param: SetStrokeColorParam) {
        for color in colorPalletModel.colors {
            let words = color.accessibilityName.split(separator: " ")
            if let name = words.last, name == param.strokeColorName {
                colorPalletModel.colorPalletEntityDisable()
                colorPalletModel.setActiveColor(color: color)
                paintingCanvas.setActiveColor(color: color)
                break
            }
        }
    }
    
    /// これまでに書いた全てのストロークを削除する
    func removeAllStroke() {
        // これまでに書いたストロークを表示から削除
        paintingCanvas.root.children.removeAll()
        // これまでに書いたストロークをデータから削除
        paintingCanvas.strokes.removeAll()
    }
    
    /// 指定したUUIDを `StrokeComponent` に持つストロークを削除する
    func removeStroke(param: RemoveStrokeParam){
        paintingCanvas.strokes.removeAll{ $0.entity.components[StrokeComponent.self]?.uuid == param.uuid
        }
        
        DispatchQueue.main.async {
            let childrenToRemove = self.paintingCanvas.root.children.filter {
                $0.components[StrokeComponent.self]?.uuid == param.uuid
            }
            for child in childrenToRemove {
                child.removeFromParent()
            }
        }
    }
    
    /// ストロークを描く
    /// - Parameter point: 描く座標
    func addStrokePoint(param: AddStrokePointParam) {
        paintingCanvas.addPoint(param.uuid, param.point)
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
            let uuid: UUID
        }
        
        struct AddStrokePointParam: Codable {
            let uuid: UUID
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
typealias RemoveAllStrokesParam = PaintingEntity.Param.RemoveAllStrokeParam
typealias RemoveStrokeParam = PaintingEntity.Param.RemoveStrokeParam
typealias AddStrokePointParam = PaintingEntity.Param.AddStrokePointParam
typealias FinishStrokeParam = PaintingEntity.Param.FinishStrokeParam
