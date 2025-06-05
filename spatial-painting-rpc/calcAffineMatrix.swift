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
        var dot:[Double] = [0, 0, 0, 0]
        for j in stride(from: 3, through: i+1, by: -1) {
           for k in 0..<4 {
               dot[k] += U[i][j] * X[j][k]
           }
        }
        for k in 0..<4 {
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

func rotation(_ myAffineMatrix: [[Double]] ,_ otherAffineMatrix: [[Double]], _ affineMatrix: [[Double]]) -> [[Double]] {
    let myRotationX = atan2(myAffineMatrix[2][1], myAffineMatrix[2][2])
    let myRotationY = atan2(-myAffineMatrix[2][0], sqrt(pow(myAffineMatrix[2][1], 2) + pow(myAffineMatrix[2][2], 2)))
    let myRotationZ = atan2(myAffineMatrix[1][0], myAffineMatrix[0][0])
    
    let otherRotationX = atan2(otherAffineMatrix[2][1], otherAffineMatrix[2][2])
    let otherRotationY = atan2(-otherAffineMatrix[2][0], sqrt(pow(otherAffineMatrix[2][1], 2) + pow(otherAffineMatrix[2][2], 2)))
    let otherRotationZ = atan2(otherAffineMatrix[1][0], otherAffineMatrix[0][0])
    
    let theta_x = myRotationX - otherRotationX
    let theta_y = myRotationY - otherRotationY
    let theta_z = myRotationZ - otherRotationZ
    
    let theta_x_rotation = [
        [1, 0, 0, 0],
        [0, cos(theta_x), -sin(theta_x), 0],
        [0, sin(theta_x), cos(theta_x), 0],
        [0, 0, 0, 1]
    ]
    let theta_y_rotation = [
        [cos(theta_y), 0, sin(theta_y), 0],
        [0, 1, 0, 0],
        [-sin(theta_y), 0, cos(theta_y), 0],
        [0, 0, 0, 1]
    ]
    let theta_z_rotation = [
        [cos(theta_z), -sin(theta_z), 0, 0],
        [sin(theta_z), cos(theta_z), 0, 0],
        [0, 0, 1, 0],
        [0, 0, 0, 1]
    ]
    
    
    let rotationMatrix = matmul(matmul(theta_x_rotation, theta_y_rotation), theta_z_rotation)
    
    return [
        [rotationMatrix[0][0], rotationMatrix[0][1], rotationMatrix[0][2], affineMatrix[0][3]],
        [rotationMatrix[1][0], rotationMatrix[1][1], rotationMatrix[1][2], affineMatrix[1][3]],
        [rotationMatrix[2][0], rotationMatrix[2][1], rotationMatrix[2][2], affineMatrix[2][3]],
        [0, 0, 0, 1]
    ]
}

func affineMatrixToAngle(_ matrix: [[Double]]) -> (Double, Double, Double) {
    let x = atan2(matrix[2][1], matrix[2][2])
    let y = atan2(-matrix[2][0], sqrt(pow(matrix[2][1], 2) + pow(matrix[2][2], 2)))
    let z = atan2(matrix[1][0], matrix[0][0])
    return (x, y, z)
}

func shiftRotateAffineMatrix(_ A: [[[Double]]], _ B: [[[Double]]], _ affineMatrix: [[Double]]) -> [[Double]] {
    var tmpAffineMatrix = rotation(A[0], B[0], affineMatrix)
    return tmpAffineMatrix
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
    let n = A.count

    var P:[[Double]] = []
    for i in (0..<n) {
        var rowP:[Double] = []
        for j in (0..<3) {
            rowP.append(A[i][j][3])
        }
        rowP.append(1.0)
        P.append(rowP)
    }
    if P.count == 3 {
        P.append([0, 0, 0, 0])
    }
    
    var Q:[[Double]] = []
    for i in (0..<n) {
        var rowQ:[Double] = []
        for j in (0..<3) {
            rowQ.append(B[i][j][3])
        }
        rowQ.append(0.0)
        Q.append(rowQ)
    }
    if Q.count == 3 {
        Q.append([0, 0, 0, 0])
    }
    
    let eqSolveMatrix:[[Double]] = matrixMul4x4(eqSolve(matrixMul4x4(P.transpose4x4, P), P.transpose4x4), Q)
    var affineMatrix:[[Double]] = eqSolveMatrix.transpose4x4
    affineMatrix[3][3] = 1.0
    print("default")
    print(affineMatrix)
    
    affineMatrix = removeScaleAffineMatrix(affineMatrix)
    print("removeScaleAffineMatrix")
    print(affineMatrix)
    
//    let rotateAffineMatrix = shiftRotateAffineMatrix(A, B, affineMatrix)
//    print("shiftRotateAffineMatrix")
//    print(rotateAffineMatrix)
//    if !rotateAffineMatrix.isIncludeNaN {
//        affineMatrix = rotateAffineMatrix
//    }
    
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
