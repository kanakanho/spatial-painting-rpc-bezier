//
//  CalculateTransformationMatrix.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/02/07.
//

import simd
import Accelerate

func matmul(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
    let rowsA = A.count
    let colsA = A[0].count
    let colsB = B[0].count
    
    var result = Array(repeating: Array(repeating: 0.0, count: colsB), count: rowsA)
    for i in 0..<rowsA {
        for j in 0..<colsB {
            for k in 0..<colsA {
                result[i][j] += A[i][k] * B[k][j]
            }
        }
    }
    return result
}

func matrixMul4x4(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
    var result = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
    for i in 0..<4 {
        for j in 0..<4 {
            for k in 0..<4 {
                result[i][j] += A[i][k] * B[k][j]
            }
        }
    }
    return result
}

func LU(_ A: [[Double]]) -> ([[Double]], [[Double]]) {
    var L = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
    var U = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
    
    for i in 0..<4 {
        L[i][i] = 1  // 対角成分は1
        
        for j in i..<4 {
            var sum: Double = 0.0
            for k in 0..<i {
                sum += L[i][k] * U[k][j]
            }
            U[i][j] = A[i][j] - sum
        }
        
        for j in (i+1)..<4 {
            var sum: Double = 0.0
            for k in 0..<i {
                sum += L[j][k] * U[k][i]
            }
            L[j][i] = (A[j][i] - sum) / (U[i][i])
        }
    }
    
    return (L, U)
}

func eqSolve(_ A: [[Double]], _ Q: [[Double]]) -> [[Double]] {
    var (L, U) = LU(A)
    var Y = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
    var X = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
    
    // 前進代入 L * Y = Q
    for i in 0..<4 {
        var dot = [Double](repeating: 0, count: 4)
        for j in 0..<i {
            for k in 0..<4 {
                dot[k] += L[i][j] * Y[j][k]
            }
        }
        
        for k in 0..<4 {
            Y[i][k] = Q[i][k] - dot[k]
        }
    }
    
    // 後退代入 U * X = Y
    for i in stride(from: 3, through: 0, by: -1) {
        if abs(U[i][i]) < 1e-8 {  // 0除算防止
            print("Warning: U[\(i), \(i)] is nearly zero. Adding small value.")
            U[i][i] = 1e-8
        }
        var dot:[Double] = [0, 0, 0]
        for j in stride(from: 3, through: i+1, by: -1) {
            for k in 0..<3 {
                dot[k] += U[i][j] * X[j][k]
            }
        }
        for k in 0..<3 {
            X[i][k] = (Y[i][k] - dot[k]) / U[i][i]
        }
    }
    
    return X
}

func svd(_ matrix: simd_double3x3) -> (U: simd_double3x3, S: simd_double3, V: simd_double3x3) {
    var a: [Double] = [
        matrix[0][0], matrix[0][1], matrix[0][2],
        matrix[1][0], matrix[1][1], matrix[1][2],
        matrix[2][0], matrix[2][1], matrix[2][2]
    ]
    var s = [Double](repeating: 0, count: 3)
    var u = [Double](repeating: 0, count: 9)
    var vt = [Double](repeating: 0, count: 9)
    var info = __CLPK_integer(0)
    var lwork = __CLPK_integer(-1)
    var work = [Double](repeating: 0, count: 1)
    
    var m = __CLPK_integer(3)
    var n = __CLPK_integer(3)
    var lda = m
    var ldu = m
    var ldvt = n
    var jobu: Int8 = 65 // 'A'
    var jobvt: Int8 = 65 // 'A'
    
    // Query and allocate the optimal workspace
    dgesvd_(&jobu, &jobvt, &m, &n, &a, &lda, &s, &u, &ldu, &vt, &ldvt, &work, &lwork, &info)
    
    lwork = __CLPK_integer(work[0])
    work = [Double](repeating: 0, count: Int(lwork))
    
    // Compute SVD
    dgesvd_(&jobu, &jobvt, &m, &n, &a, &lda, &s, &u, &ldu, &vt, &ldvt, &work, &lwork, &info)
    
    var U = simd_double3x3()
    var V = simd_double3x3()
    var S = simd_double3()
    
    for i in 0..<3 {
        S[i] = s[i]
        for j in 0..<3 {
            U[j][i] = u[i * 3 + j]
            V[i][j] = vt[j * 3 + i]
        }
    }
    
    return (U, S, V)
}

func dotsimd_double3x3(_ a: simd_double3x3,_ b: simd_double3x3) -> simd_double3x3 {
    var result = simd_double3x3()
    for i in 0..<3 {
        for j in 0..<3 {
            result[i][j] = a[i].x * b[0][j] + a[i].y * b[1][j] + a[i].z * b[2][j]
        }
    }
    return result
}

func polar(_ M: simd_double3x3) -> (simd_double3x3,simd_double3x3) {
    let (w,_,vh) = svd(M)
    // 内積を計算
    let u = simd_mul(vh, w)
    let p:simd_double3x3 = .init()
    return (u,p)
}

func removeScaleAffineMatrix(_ matrix: [[Double]]) -> [[Double]] {
    // 3x3 部分行列 (回転 + スケーリング)
    let M = simd_double3x3(
        SIMD3<Double>(matrix[0][0], matrix[1][0], matrix[2][0]),
        SIMD3<Double>(matrix[0][1], matrix[1][1], matrix[2][1]),
        SIMD3<Double>(matrix[0][2], matrix[1][2], matrix[2][2])
    )
    
    // 特異値分解
    let (R,_)  = polar(M)
    
    var newMatrix = matrix
    
    for i in 0..<3 {
        for j in 0..<3 {
            newMatrix[i][j] = Double(R[i][j])
        }
    }
    
    return newMatrix
}

func matmul4x4_4x1(_ A: [[Double]], _ B: [Double]) -> [Double] {
    var result = [Double](repeating: 0, count: 4)
    for i in 0..<4 {
        for j in 0..<3 {
            result[i] += A[i][j] * B[j]
        }
        result[i] += A[i][3]
    }
    return result
}

func rotation(axis: String, _ mine_hand_arrows_shift: [[Double]] ,_ world_hand_arrows_shfit: [[Double]], _ affineMatrix: [[Double]]) -> [[Double]] {
    var world_arrows_shift:[Double] = []
    switch axis {
    case "x":
        world_arrows_shift = world_hand_arrows_shfit[1]
    case "y":
        world_arrows_shift = world_hand_arrows_shfit[2]
    case "z":
        world_arrows_shift = world_hand_arrows_shfit[3]
    default:
        return[]
    }
    
    var mine_arrows_shift:[Double] = []
    switch axis {
    case "x":
        mine_arrows_shift = mine_hand_arrows_shift[1]
    case "y":
        mine_arrows_shift = mine_hand_arrows_shift[2]
    case "z":
        mine_arrows_shift = mine_hand_arrows_shift[3]
    default:
        return[]
    }
    
    if world_arrows_shift.count != 3 {
        print("Error: world_arrows_shift must be 3 elements")
        return []
    }
    
    if mine_arrows_shift.count != 3 {
        print("Error: mine_arrows_shift must be 3 elements")
        return []
    }
    
    var theta_x = asin(world_arrows_shift[0])
    if axis == "x" {
        let mine_theta_x = asin(mine_arrows_shift[0])
        theta_x = mine_theta_x - theta_x
    }
    let theta_x_rotation = [
        [1, 0, 0, 0],
        [0, cos(theta_x), -sin(theta_x), 0],
        [0, sin(theta_x), cos(theta_x), 0],
        [0, 0, 0, 1]
    ]
    
    var theta_y = asin(world_arrows_shift[1])
    if axis == "y" {
        let mine_theta_y = asin(mine_arrows_shift[1])
        theta_y = mine_theta_y - theta_y
    }
    let theta_y_rotation = [
        [cos(theta_y), 0, sin(theta_y), 0],
        [0, 1, 0, 0],
        [-sin(theta_y), 0, cos(theta_y), 0],
        [0, 0, 0, 1]
    ]
    
    var theta_z = asin(world_arrows_shift[2])
    if axis == "z" {
        let mine_theta_z = asin(mine_arrows_shift[2])
        theta_z = mine_theta_z - theta_z
    }
    let theta_z_rotation = [
        [cos(theta_z), -sin(theta_z), 0, 0],
        [sin(theta_z), cos(theta_z), 0, 0],
        [0, 0, 1, 0],
        [0, 0, 0, 1]
    ]
    
    let rotationMatrix = matmul(matmul(theta_x_rotation, theta_y_rotation), theta_z_rotation)
    
    switch axis {
    case "x":
        let returnAffineMatrix = [
            [rotationMatrix[0][0], rotationMatrix[0][1], rotationMatrix[0][2], affineMatrix[0][3]],
            [rotationMatrix[1][0], rotationMatrix[1][1], rotationMatrix[1][2], affineMatrix[1][3]],
            [rotationMatrix[2][0], rotationMatrix[2][1], rotationMatrix[2][2], affineMatrix[2][3]],
            [0, 0, 0, 1]
        ]
        return returnAffineMatrix
    case "y":
        let returnAffineMatrix = [
            [rotationMatrix[0][0], rotationMatrix[0][1], rotationMatrix[0][2], affineMatrix[0][3]],
            [rotationMatrix[1][0], rotationMatrix[1][1], rotationMatrix[1][2], affineMatrix[1][3]],
            [rotationMatrix[2][0], rotationMatrix[2][1], rotationMatrix[2][2], affineMatrix[2][3]],
            [0, 0, 0, 1]
        ]
        return returnAffineMatrix
    case "z":
        let returnAffineMatrix = [
            [rotationMatrix[0][0], rotationMatrix[0][1], rotationMatrix[0][2], affineMatrix[0][3]],
            [rotationMatrix[1][0], rotationMatrix[1][1], rotationMatrix[1][2], affineMatrix[1][3]],
            [rotationMatrix[2][0], rotationMatrix[2][1], rotationMatrix[2][2], affineMatrix[2][3]],
            [0, 0, 0, 1]
        ]
        return returnAffineMatrix
    default:
        return []
    }
}

func affineMatrixToAngle(_ matrix: [[Double]]) -> (Double, Double, Double) {
    let x = atan2(matrix[2][1], matrix[2][2])
    let y = atan2(-matrix[2][0], sqrt(pow(matrix[2][1], 2) + pow(matrix[2][2], 2)))
    let z = atan2(matrix[1][0], matrix[0][0])
    return (x, y, z)
}

func shiftRotateAffineMatrix(_ A: [[[Double]]], _ B: [[[Double]]], _ affineMatrix: [[Double]]) -> [[Double]] {
    // Bの位置を取得
    let B_pos = [B[0][0][3], B[0][1][3], B[0][2][3]]
    
    let (x,y,z) = affineMatrixToAngle(B[0])
    
    // B基準の単位ベクトル群（+X, +Y, +Z 方向）
    var B_vectors: [[Double]] = [
        B_pos,
        [B_pos[0] + cos(x), B_pos[1] + cos(y), B_pos[2] + cos(z)],
        [B_pos[0] + cos(z), B_pos[1] + cos(x), B_pos[2] + cos(y)],
        [B_pos[0] + cos(y), B_pos[1] + cos(z), B_pos[2] + cos(x)]
    ]
    
    // 正規化
    let B_vectors_norm = B_vectors.map { sqrt(pow($0[0], 2) + pow($0[1], 2) + pow($0[2], 2)) }
    B_vectors = B_vectors.map { $0.map { $0 / B_vectors_norm[0] } }
    
    // affineMatrixでB_vectorsをA空間に変換
    let transformedVectors = B_vectors.map { matmul4x4_4x1(affineMatrix, $0) }
    
    // シフト量（最初の点の差）
    let shift = zip(transformedVectors[0], B_vectors[0]).map { $0 - $1 }
    
    // B側ベクトルを原点相対にシフト
    let shifted_B_vectors = B_vectors.map { zip($0, shift).map(-) }
    let B_origin = shifted_B_vectors[0]
    let B_relative = shifted_B_vectors.map { zip($0, B_origin).map(-) }
    
    // A側も同様にシフト
    let shifted_transformed = transformedVectors.map { zip($0, shift).map(-) }
    let A_origin = shifted_transformed[0]
    let A_relative = shifted_transformed.map { zip($0, A_origin).map(-) }
    
    // 回転補正（Y→Z→Xの順）
    let yMatrix = rotation(axis: "y", B_relative, A_relative, affineMatrix)
    
    return yMatrix
}


/*
 let A:[[[Double]]] = [
 [[1, 0, 0, 7],[0, 1, 0, 9],[0, 0, 1, 8],[0, 0, 0, 1]],
 [[1, 0, 0, 7],[0, 1, 0, 7],[0, 0, 1, 8],[0, 0, 0, 1]],
 [[1, 0, 0, 23],[0, 1, 0, 25],[0, 0, 1, 23],[0, 0, 0, 1]],
 ]
 
 let B:[[[Double]]] = [
 [[1, 0, 0, 13],[0, 1, 0, 15],[0, 0, 1, 14],[0, 0, 0, 1]],
 [[1, 0, 0, 15],[0, 1, 0, 15],[0, 0, 1, 16],[0, 0, 0, 1]],
 [[1, 0, 0, 33],[0, 1, 0, 35],[0, 0, 1, 33],[0, 0, 0, 1]],
 ]
 
 calcAffineMatrix(A, B)
 */
func calcAffineMatrix(_ A: [[[Double]]], _ B: [[[Double]]]) -> [[Double]] {
    print("A")
    print(A)
    print("B")
    print(B)
    var P:[[Double]] = []
    for i in (0..<3) {
        var rowP:[Double] = []
        for j in (0..<3) {
            rowP.append(A[i][j][3])
        }
        rowP.append(1.0)
        P.append(rowP)
    }
    P.append([0, 0, 0, 0])
    
    var Q:[[Double]] = []
    for i in (0..<3) {
        var rowQ:[Double] = []
        for j in (0..<3) {
            rowQ.append(B[i][j][3])
        }
        rowQ.append(0.0)
        Q.append(rowQ)
    }
    Q.append([0, 0, 0, 0])
    
    let eqSolveMatrix:[[Double]] = matrixMul4x4(eqSolve(matrixMul4x4(P.transpose4x4, P), P.transpose4x4), Q)
    var affineMatrix:[[Double]] = eqSolveMatrix.transpose4x4
    affineMatrix[3][3] = 1.0
    print("default")
    print(affineMatrix)
    
    affineMatrix = removeScaleAffineMatrix(affineMatrix)
    print("removeScaleAffineMatrix")
    print(affineMatrix)
    
    //    affineMatrix = shiftRotateAffineMatrix(A, B, affineMatrix)
    //    print("shiftRotateAffineMatrix")
    //    print(affineMatrix)
    
    return affineMatrix
}

// 逆行列を計算する関数
func inverseMatrix(_ matrix: [[Double]]) -> [[Double]] {
    let n = matrix.count
    guard n == 4 else {
        fatalError("Only 4x4 matrices are supported.")
    }
    
    var augmentedMatrix = matrix
    var identityMatrix = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
    
    // 単位行列を作成
    for i in 0..<n {
        identityMatrix[i][i] = 1.0
    }
    
    // 拡大行列を作成
    for i in 0..<n {
        augmentedMatrix[i].append(contentsOf: identityMatrix[i])
    }
    
    // ガウス・ジョルダン法で逆行列を計算
    for i in 0..<n {
        // 対角成分を1にする
        let diagElement = augmentedMatrix[i][i]
        if abs(diagElement) < 1e-8 {
            fatalError("Matrix is singular and cannot be inverted.")
        }
        for j in 0..<(2 * n) {
            augmentedMatrix[i][j] /= diagElement
        }
        
        // 他の行を0にする
        for k in 0..<n {
            if k != i {
                let factor = augmentedMatrix[k][i]
                for j in 0..<(2 * n) {
                    augmentedMatrix[k][j] -= factor * augmentedMatrix[i][j]
                }
            }
        }
    }
    
    // 逆行列を抽出
    var inverseMatrix = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
    for i in 0..<n {
        inverseMatrix[i] = Array(augmentedMatrix[i][n..<(2 * n)])
    }
    
    return inverseMatrix
}
