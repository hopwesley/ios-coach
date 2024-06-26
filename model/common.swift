//
//  test_util.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/18.
//

import Foundation
import simd

let DescriptorParam_M = 2
let DescriptorParam_m = 4
let SideSizeOfLevelZero = 32
let PixelThreadWidth = 8
let PixelThreadHeight = 8
let HistogramSize = 10
let ThreadSizeForParallelSum = 32

let phi = Float((1.0 + sqrt(5.0)) / 2.0)
let icosahedronCenterP: [SIMD3<Float>] = [
    SIMD3(0, 1 / phi, phi),
    SIMD3(0, -1 / phi, phi),
    SIMD3(0, 1 / phi, -phi),
    SIMD3(0, -1 / phi, -phi),
    SIMD3(1 / phi, phi, 0),
    SIMD3(-1 / phi, phi, 0),
    SIMD3(1 / phi, -phi, 0),
    SIMD3(-1 / phi, -phi, 0),
    SIMD3(phi, 0, 1 / phi),
    SIMD3(-phi, 0, 1 / phi),
    SIMD3(phi, 0, -1 / phi),
    SIMD3(-phi, 0, -1 / phi),
    SIMD3(1, 1, 1),
    SIMD3(-1, 1, 1),
    SIMD3(1, -1, 1),
    SIMD3(-1, -1, 1),
    SIMD3(1, 1, -1),
    SIMD3(-1, 1, -1),
    SIMD3(1, -1, -1),
    SIMD3(-1, -1, -1)
]

let normalizedP: [SIMD3<Float>] = icosahedronCenterP.map { normalize($0) }
