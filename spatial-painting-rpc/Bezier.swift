import Foundation
import Accelerate
import simd

// MARK: - ベジェ点評価

func cubicBezierPoint3D(p0: SIMD3<Double>, p1: SIMD3<Double>, p2: SIMD3<Double>, p3: SIMD3<Double>, t: Double) -> SIMD3<Double> {
    let u = 1 - t
    return u * u * u * p0
         + 3 * u * u * t * p1
         + 3 * u * t * t * p2
         + t * t * t * p3
}

func points2fittedBeziers(points: [SIMD3<Float>], max_error: Double = 0.0001) -> [[SIMD3<Double>]] {
    let points_d: [Point] = points.map { Point(Double($0.x), Double($0.y), Double($0.z)) }
    let fittedBeziers: [[Point]] = BezierFitter.fitCurve(points: points_d, maxError: max_error)
    return fittedBeziers
}

/// 3次元の点またはベクトルを表す型エイリアス。
public typealias Point = SIMD3<Double>

/// ベジェ曲線の計算をまとめた構造体。
public struct Bezier {
    /// 3次ベジェ曲線をパラメータtで評価します。
    /// B(t) = (1-t)^3 P0 + 3(1-t)^2 t P1 + 3(1-t) t^2 P2 + t^3 P3
    /// - Parameters:
    ///   - controlPoints: 4つの制御点 [P0, P1, P2, P3]。
    ///   - t: パラメータ (通常0から1の範囲)。
    /// - Returns: 曲線上の点。
    public static func q(controlPoints: [Point], t: Double) -> Point {
        let tx = 1.0 - t
        let pA = controlPoints[0] * pow(tx, 3)
        let pB = controlPoints[1] * (3 * pow(tx, 2) * t)
        let pC = controlPoints[2] * (3 * tx * pow(t, 2))
        let pD = controlPoints[3] * pow(t, 3)
        return pA + pB + pC + pD
    }

    /// 3次ベジェ曲線の一次導関数をパラメータtで評価します。
    /// B'(t) = 3(1-t)^2(P1-P0) + 6(1-t)t(P2-P1) + 3t^2(P3-P2)
    /// - Parameters:
    ///   - controlPoints: 4つの制御点 [P0, P1, P2, P3]。
    ///   - t: パラメータ。
    /// - Returns: 曲線上の点における接線ベクトル。
    public static func qprime(controlPoints: [Point], t: Double) -> Point {
        let tx = 1.0 - t
        let pA = (controlPoints[1] - controlPoints[0]) * (3 * pow(tx, 2))
        let pB = (controlPoints[2] - controlPoints[1]) * (6 * tx * t)
        let pC = (controlPoints[3] - controlPoints[2]) * (3 * pow(t, 2))
        return pA + pB + pC
    }

    /// 3次ベジェ曲線の二次導関数をパラメータtで評価します。
    /// B''(t) = 6(1-t)(P2-2P1+P0) + 6t(P3-2P2+P1)
    /// - Parameters:
    ///   - controlPoints: 4つの制御点 [P0, P1, P2, P3]。
    ///   - t: パラメータ。
    /// - Returns: 曲線上の点における曲率に関連するベクトル。
    public static func qprimeprime(controlPoints: [Point], t: Double) -> Point {
        let pA = (controlPoints[2] - 2 * controlPoints[1] + controlPoints[0]) * (6 * (1.0 - t))
        let pB = (controlPoints[3] - 2 * controlPoints[2] + controlPoints[1]) * (6 * t)
        return pA + pB
    }
}


/// 点群にベジェ曲線をフィットさせるための構造体。
struct BezierFitter {

    /// フィッティングの進捗状況を通知するためのデータ構造。
    public struct ProgressData {
        public let bezierCurve: [Point]
        public let points: [Point]
        public let parameters: [Double]
        public let maxError: Double
        public let splitPointIndex: Int
    }
    
    /// 進捗状況を通知するためのコールバッククロージャの型エイリアス。
    public typealias ProgressCallback = (ProgressData) -> Void

    /// 一連の点に1つまたは複数のベジェ曲線をフィットさせます。
    /// - Parameters:
    ///   - points: フィットさせる点の配列。
    ///   - maxError: 許容される最大二乗誤差。
    ///   - progressCallback: フィッティングの各イテレーションの進捗を通知するコールバック。
    /// - Returns: フィットしたベジェ曲線の制御点の配列の配列。
    public static func fitCurve(points: [Point], maxError: Double,
                                progressCallback: ProgressCallback? = nil) -> [[Point]] {
        guard !points.isEmpty else {
            print("Error: First argument must be a non-empty list of points.")
            return []
        }

        // 近すぎる重複点を除去
        var uniquePoints = [Point]()
        if let first = points.first {
            uniquePoints.append(first)
            for i in 1..<points.count {
                if distance(points[i], points[i-1]) >= 1e-9 {
                    uniquePoints.append(points[i])
                }
            }
        }
        
        guard uniquePoints.count >= 2 else {
            return []
        }

        let leftTangent = createTangent(from: uniquePoints[1], to: uniquePoints[0])
        let rightTangent = createTangent(from: uniquePoints[uniquePoints.count - 2], to: uniquePoints.last!)

        return fitCubic(points: uniquePoints, leftTangent: leftTangent, rightTangent: rightTangent, error: maxError, progressCallback: progressCallback)
    }

    /// 点群のサブセットに再帰的にベジェ曲線をフィットさせます。
    private static func fitCubic(points: [Point], leftTangent: Point, rightTangent: Point, error: Double, progressCallback: ProgressCallback?) -> [[Point]] {
        let maxIterations = 20

        // 点が2つしかない場合は、直線的なベジェ曲線を作成
        if points.count == 2 {
            let dist = distance(points[0], points[1]) / 3.0
            let bezCurve = [
                points[0],
                points[0] + leftTangent * dist,
                points[1] + rightTangent * dist,
                points[1]
            ]
            return [bezCurve]
        }
        
        // 弦長に基づいて点をパラメータ化
        let u = chordLengthParameterize(points: points)
        var (bezCurve, maxError, splitPoint) = generateAndReport(
            points: points, paramsOrig: u, paramsPrime: u,
            leftTangent: leftTangent, rightTangent: rightTangent,
            progressCallback: progressCallback
        )

        // エラーが許容範囲内なら、この曲線を採用
        if maxError < error {
            return [bezCurve]
        }

        // エラーが大きい場合、パラメータを再計算して改善を試みる
        if maxError < error * error {
            var uPrime = u
            var prevErr = maxError
            var prevSplit = splitPoint

            for _ in 0..<maxIterations {
                uPrime = reparameterize(bezierCurve: bezCurve, points: points, parameters: uPrime)
                (bezCurve, maxError, splitPoint) = generateAndReport(
                    points: points, paramsOrig: u, paramsPrime: uPrime,
                    leftTangent: leftTangent, rightTangent: rightTangent,
                    progressCallback: progressCallback
                )
                if maxError < error {
                    return [bezCurve]
                }
                
                // 収束判定
                if splitPoint == prevSplit {
                    let errChange = maxError / prevErr
                    if (0.9999 < errChange && errChange < 1.0001) {
                        break
                    }
                }
                prevErr = maxError
                prevSplit = splitPoint
            }
        }

        // 改善が見られない場合、最もエラーの大きい点で曲線を分割
        var beziers: [[Point]] = []
        var centerVector = points[splitPoint - 1] - points[splitPoint + 1]

        if length_squared(centerVector) < 1e-9 {
            let vPrev = points[splitPoint - 1] - points[splitPoint]
            let vNext = points[splitPoint + 1] - points[splitPoint]
            
            // 3点が同一直線上にある場合の処理
            if length_squared(vPrev) > 1e-9 {
                var axisVec = Point(1.0, 0.0, 0.0)
                if length_squared(cross(vPrev, axisVec)) < 1e-9 {
                    axisVec = Point(0.0, 1.0, 0.0)
                }
                centerVector = cross(vPrev, axisVec)
            } else if length_squared(vNext) > 1e-9 {
                var axisVec = Point(1.0, 0.0, 0.0)
                if length_squared(cross(vNext, axisVec)) < 1e-9 {
                    axisVec = Point(0.0, 1.0, 0.0)
                }
                centerVector = cross(vNext, axisVec)
            } else {
                centerVector = Point(1.0, 0.0, 0.0)
            }
        }
        
        let normCenterVector = normalize(centerVector)
        let toCenterTangent = normCenterVector
        let fromCenterTangent = -normCenterVector

        let leftPoints = Array(points[...splitPoint])
        beziers.append(contentsOf: fitCubic(points: leftPoints, leftTangent: leftTangent, rightTangent: toCenterTangent, error: error, progressCallback: progressCallback))
        
        let rightPoints = Array(points[splitPoint...])
        beziers.append(contentsOf: fitCubic(points: rightPoints, leftTangent: fromCenterTangent, rightTangent: rightTangent, error: error, progressCallback: progressCallback))
        
        return beziers
    }

    /// ベジェ曲線を生成し、最大誤差を計算して報告します。
    private static func generateAndReport(points: [Point], paramsOrig: [Double], paramsPrime: [Double],
                                           leftTangent: Point, rightTangent: Point,
                                           progressCallback: ProgressCallback?) -> (curve: [Point], maxError: Double, splitPoint: Int) {
        
        let bezCurve = generateBezier(points: points, parameters: paramsPrime, leftTangent: leftTangent, rightTangent: rightTangent)
        let (maxError, splitPoint) = computeMaxError(points: points, bez: bezCurve, parameters: paramsOrig)

        if let callback = progressCallback {
            callback(ProgressData(
                bezierCurve: bezCurve,
                points: points,
                parameters: paramsOrig,
                maxError: maxError,
                splitPointIndex: splitPoint
            ))
        }
        
        return (bezCurve, maxError, splitPoint)
    }

    /// 最小二乗法を用いてベジェ曲線の制御点を生成します。
    private static func generateBezier(points: [Point], parameters: [Double],
                                       leftTangent: Point, rightTangent: Point) -> [Point] {
        guard let firstPoint = points.first, let lastPoint = points.last else { return [] }

        var A = [[Point]](repeating: [Point.zero, Point.zero], count: parameters.count)
        for (i, u) in parameters.enumerated() {
            let ux = 1.0 - u
            A[i][0] = leftTangent * (3 * u * pow(ux, 2))
            A[i][1] = rightTangent * (3 * ux * pow(u, 2))
        }

        var c00 = 0.0, c01 = 0.0, c11 = 0.0
        var x0 = 0.0, x1 = 0.0

        for (i, p) in points.enumerated() {
            let a = A[i]
            c00 += dot(a[0], a[0])
            c01 += dot(a[0], a[1])
            c11 += dot(a[1], a[1])

            let u = parameters[i]
            let qDegenerate = firstPoint * (1.0 - u) + lastPoint * u
            let tmp = p - qDegenerate
            
            x0 += dot(a[0], tmp)
            x1 += dot(a[1], tmp)
        }
        let c10 = c01

        let detC0C1 = c00 * c11 - c10 * c01
        let detC0X = c00 * x1 - c10 * x0
        let detXC1 = x0 * c11 - x1 * c01

        let alphaL = abs(detC0C1) < 1e-9 ? 0.0 : detXC1 / detC0C1
        let alphaR = abs(detC0C1) < 1e-9 ? 0.0 : detC0X / detC0C1

        let segLength = distance(firstPoint, lastPoint)
        let epsilon = 1.0e-6 * segLength

        let ctrl1: Point
        let ctrl2: Point

        if alphaL < epsilon || alphaR < epsilon {
            ctrl1 = firstPoint + leftTangent * (segLength / 3.0)
            ctrl2 = lastPoint + rightTangent * (segLength / 3.0)
        } else {
            ctrl1 = firstPoint + leftTangent * alphaL
            ctrl2 = lastPoint + rightTangent * alphaR
        }
        
        return [firstPoint, ctrl1, ctrl2, lastPoint]
    }
    
    /// ニュートン・ラフソン法を用いてパラメータを再計算します。
    private static func reparameterize(bezierCurve: [Point], points: [Point], parameters: [Double]) -> [Double] {
        return zip(points, parameters).map { (p, u) in
            newtonRaphsonRootFind(bez: bezierCurve, point: p, u: u)
        }
    }

    /// ニュートン・ラフソン法で、点に最も近い曲線上のパラメータuを見つけます。
    private static func newtonRaphsonRootFind(bez: [Point], point: Point, u: Double) -> Double {
        let d = Bezier.q(controlPoints: bez, t: u) - point
        let qprime = Bezier.qprime(controlPoints: bez, t: u)
        let numerator = dot(d, qprime)
        
        let qprimeprime = Bezier.qprimeprime(controlPoints: bez, t: u)
        let denominator = dot(qprime, qprime) + dot(d, qprimeprime)
        
        return abs(denominator) < 1e-9 ? u : u - (numerator / denominator)
    }

    /// 弦長に基づいて点群をパラメータ化します (0から1の範囲)。
    private static func chordLengthParameterize(points: [Point]) -> [Double] {
        var distances = [Double](repeating: 0.0, count: points.count)
        for i in 1..<points.count {
            distances[i] = distances[i-1] + distance(points[i], points[i-1])
        }
        
        guard let totalLength = distances.last, totalLength > 0 else {
            return (0..<points.count).map { Double($0) / Double(points.count - 1) }
        }
        
        return distances.map { $0 / totalLength }
    }

    /// 点群とベジェ曲線との間の最大二乗誤差を計算します。
    private static func computeMaxError(points: [Point], bez: [Point], parameters: [Double]) -> (maxDist: Double, splitPoint: Int) {
        var maxDist = 0.0
        var splitPoint = points.count / 2
        
        let tDistMap = mapTToRelativeDistances(bez: bez, parts: 10)

        for (i, (point, param)) in zip(points, parameters).enumerated() {
            let t = findT(bez: bez, param: param, tDistMap: tDistMap)
            let v = Bezier.q(controlPoints: bez, t: t) - point
            let dist = length_squared(v) // 二乗距離を使用

            if dist > maxDist {
                maxDist = dist
                splitPoint = i
            }
        }
        return (maxDist, splitPoint)
    }

    /// ベジェ曲線のパラメータtと相対的な弧長の対応表を作成します。
    private static func mapTToRelativeDistances(bez: [Point], parts: Int) -> [Double] {
        var distances = [0.0]
        var bTPrev = bez[0]
        
        for i in 1...parts {
            let t = Double(i) / Double(parts)
            let bTCurr = Bezier.q(controlPoints: bez, t: t)
            distances.append(distances.last! + distance(bTCurr, bTPrev))
            bTPrev = bTCurr
        }
        
        guard let totalLength = distances.last, totalLength > 0 else {
            return distances
        }
        
        return distances.map { $0 / totalLength }
    }

    /// 弧長のパラメータからベジェ曲線のパラメータtを近似的に見つけます。
    private static func findT(bez: [Point], param: Double, tDistMap: [Double]) -> Double {
        if param < 0 { return 0.0 }
        if param > 1 { return 1.0 }

        let parts = tDistMap.count - 1
        
        for i in 1...parts {
            if param <= tDistMap[i] {
                let tMin = Double(i - 1) / Double(parts)
                let tMax = Double(i) / Double(parts)
                let lenMin = tDistMap[i-1]
                let lenMax = tDistMap[i]
                
                guard lenMax > lenMin else { return tMin }

                let t = (param - lenMin) / (lenMax - lenMin) * (tMax - tMin) + tMin
                return t
            }
        }
        
        return 1.0
    }

    /// 2点間の正規化された接線ベクトルを作成します。
    private static func createTangent(from pointA: Point, to pointB: Point) -> Point {
        let vec = pointA - pointB
        return normalize(vec)
    }
}
