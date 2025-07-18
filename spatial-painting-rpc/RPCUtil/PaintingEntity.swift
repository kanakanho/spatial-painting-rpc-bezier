//
//  PaintingCanvasEintity.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/21.
//

import Foundation
import RealityFoundation
import UIKit

@MainActor
class Painting:ObservableObject {
    @Published var paintingCanvas = PaintingCanvas()
    @Published var advancedColorPalletModel = AdvancedColorPalletModel()
    
    /// 色を選択する
    /// - Parameter strokeColorName: 色の名前
    func setStrokeColor(param: SetStrokeColorParam) {
        if let color: UIColor = advancedColorPalletModel.colorDictionary[param.strokeColorName] {
            advancedColorPalletModel.colorPalletEntityDisable()
            advancedColorPalletModel.setActiveColor(color: color)
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
    
    /// 複数のストロークを追加する
    func addStrokes(param: AddStrokesParam) {
        paintingCanvas.addStrokes(param.externalStrokes.strokes())
    }
    
    /// 追加したストロークを確定する
    func confirmTmpStrokes(param: ConfirmTmpStrokesParam) {
        paintingCanvas.confirmTmpStrokes()
    }
    
    /// 線の太さを変更する
    func changeFingerLineWidth(param: ChangeFingerLineWidthParam) {
        //print("Finger line width changed to: \(toolName)")
        if advancedColorPalletModel.selectedToolName == param.toolName {
            return
        }
//        let toolBall = advancedColorPalletModel.toolBalls.get(withID: param.toolName)
//        if toolBall == nil {
//            
//        }
        advancedColorPalletModel.selectedToolName = param.toolName
    }
}

struct PaintingEntity: RPCEntity {
    enum Method: RPCEntityMethod {
        case setStrokeColor
        case removeAllStroke
        case removeStroke
        case addStrokePoint
        case addStrokes
        case finishStroke
        case changeFingerLineWidth
        case confirmTmpStrokes
    }
    
    enum Param: RPCEntityParam {
        case setStrokeColor(SetStrokeColorParam)
        case removeAllStroke(RemoveAllStrokeParam)
        case removeStroke(RemoveStrokeParam)
        case addStrokePoint(AddStrokePointParam)
        case addStrokes(AddStrokesParam)
        case finishStroke(FinishStrokeParam)
        case changeFingerLineWidth(ChangeFingerLineWidthParam)
        case confirmTmpStrokes(ConfirmTmpStrokesParam)
        
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
        
        struct AddStrokesParam: Codable {
            let externalStrokes: [ExternalStroke]
        }
        
        struct FinishStrokeParam: Codable {
        }
        
        struct ChangeFingerLineWidthParam: Codable {
            let toolName: String
        }
        
        struct ConfirmTmpStrokesParam: Codable {
            let externalStrokes: [ExternalStroke]
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
            case .addStrokes(let param):
                try container.encode(param, forKey: .addStrokes)
            case .finishStroke(let param):
                try container.encode(param, forKey: .finishStroke)
            case .changeFingerLineWidth(let param):
                try container.encode(param, forKey: .changeFingerLineWidth)
            case .confirmTmpStrokes(let param):
                try container.encode(param, forKey: .confirmTmpStrokes)
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
            } else if let param = try? container.decode(AddStrokesParam.self, forKey: .addStrokes) {
                self = .addStrokes(param)
            } else if let param = try? container.decode(FinishStrokeParam.self, forKey: .finishStroke) {
                self = .finishStroke(param)
            } else if let param = try? container.decode(ChangeFingerLineWidthParam.self, forKey: .changeFingerLineWidth) {
                self = .changeFingerLineWidth(param)
            } else if let param = try? container.decode(ConfirmTmpStrokesParam.self, forKey: .confirmTmpStrokes) {
                self = .confirmTmpStrokes(param)
            } else {
                throw DecodingError.dataCorruptedError(forKey: CodingKeys.setStrokeColor, in: container, debugDescription: "Invalid parameter type")
            }
        }
        
        internal enum CodingKeys: CodingKey {
            case setStrokeColor
            case removeAllStroke
            case removeStroke
            case addStrokePoint
            case addStrokes
            case finishStroke
            case changeFingerLineWidth
            case confirmTmpStrokes
        }
    }
}

typealias SetStrokeColorParam = PaintingEntity.Param.SetStrokeColorParam
typealias RemoveAllStrokesParam = PaintingEntity.Param.RemoveAllStrokeParam
typealias RemoveStrokeParam = PaintingEntity.Param.RemoveStrokeParam
typealias AddStrokePointParam = PaintingEntity.Param.AddStrokePointParam
typealias AddStrokesParam = PaintingEntity.Param.AddStrokesParam
typealias FinishStrokeParam = PaintingEntity.Param.FinishStrokeParam
typealias ChangeFingerLineWidthParam = PaintingEntity.Param.ChangeFingerLineWidthParam
typealias ConfirmTmpStrokesParam = PaintingEntity.Param.ConfirmTmpStrokesParam
