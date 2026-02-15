//
//  GaussianSplatTypes.swift
//  ItemManager
//
//  3D Gaussian Splatting 数据类型定义
//  用于 Swift 和 Metal Shader 之间的数据共享
//

import Foundation
import simd
import Metal

// MARK: - 高斯点数据结构 (与 Metal Shader 对齐)

/// 单个高斯点的完整数据
/// 内存布局: 16字节对齐，总大小 80 bytes
public struct GaussianPoint {
    /// 位置 (x, y, z) - 12 bytes
    public var position: SIMD3<Float>
    
    /// 旋转四元数 (x, y, z, w) - 16 bytes
    public var rotation: SIMD4<Float>
    
    /// 缩放 (x, y, z) - 12 bytes
    public var scale: SIMD3<Float>
    
    /// 不透明度 - 4 bytes
    public var opacity: Float
    
    /// 球谐系数 (使用 half 精度，16个系数) - 32 bytes
    /// 存储前3阶球谐系数 (RGB各16个 half = 48 bytes，压缩到32 bytes)
    public var shCoefficients: (UInt16, UInt16, UInt16, UInt16,
                                UInt16, UInt16, UInt16, UInt16,
                                UInt16, UInt16, UInt16, UInt16,
                                UInt16, UInt16, UInt16, UInt16)
    
    public init(
        position: SIMD3<Float>,
        rotation: SIMD4<Float>,
        scale: SIMD3<Float>,
        opacity: Float,
        shCoefficients: [Float]
    ) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.opacity = opacity
        
        // 将 float 转换为 half (UInt16)
        var coeffs: [UInt16] = Array(repeating: 0, count: 16)
        for i in 0..<min(16, shCoefficients.count) {
            coeffs[i] = floatToHalf(shCoefficients[i])
        }
        self.shCoefficients = (
            coeffs[0], coeffs[1], coeffs[2], coeffs[3],
            coeffs[4], coeffs[5], coeffs[6], coeffs[7],
            coeffs[8], coeffs[9], coeffs[10], coeffs[11],
            coeffs[12], coeffs[13], coeffs[14], coeffs[15]
        )
    }
    
    /// 空初始化
    public init() {
        self.position = SIMD3<Float>(0, 0, 0)
        self.rotation = SIMD4<Float>(0, 0, 0, 1)
        self.scale = SIMD3<Float>(0.01, 0.01, 0.01)
        self.opacity = 1.0
        self.shCoefficients = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }
}

// MARK: - 辅助函数

/// Float 转 Half (IEEE 754 half-precision)
private func floatToHalf(_ value: Float) -> UInt16 {
    var src = value
    var dst: UInt16 = 0
    let srcBits = src.bitPattern
    
    let sign = (srcBits >> 31) & 0x1
    var exponent = Int((srcBits >> 23) & 0xFF)
    var mantissa = srcBits & 0x7FFFFF
    
    if exponent == 255 {
        // Inf or NaN
        dst = UInt16((sign << 15) | 0x7C00 | (mantissa != 0 ? 1 : 0))
    } else if exponent > 127 + 15 {
        // Overflow to infinity
        dst = UInt16((sign << 15) | 0x7C00)
    } else if exponent <= 127 - 15 {
        // Underflow to zero
        dst = UInt16(sign << 15)
    } else {
        // Normal number
        exponent = exponent - 127 + 15
        mantissa = mantissa >> 13
        dst = UInt16((sign << 15) | (UInt32(exponent) << 10) | mantissa)
    }
    
    return dst
}

/// Half 转 Float
private func halfToFloat(_ value: UInt16) -> Float {
    let sign = (UInt32(value) >> 15) & 0x1
    var exponent = Int((UInt32(value) >> 10) & 0x1F)
    var mantissa = UInt32(value) & 0x3FF
    
    var result: UInt32
    
    if exponent == 0 {
        if mantissa == 0 {
            // Zero
            result = sign << 31
        } else {
            // Denormalized number
            exponent = 1
            while (mantissa & 0x400) == 0 {
                mantissa <<= 1
                exponent -= 1
            }
            mantissa &= 0x3FF
            exponent = exponent - 15 + 127
            result = (sign << 31) | (UInt32(exponent) << 23) | (mantissa << 13)
        }
    } else if exponent == 31 {
        // Inf or NaN
        result = (sign << 31) | 0x7F800000 | (mantissa << 13)
    } else {
        // Normal number
        exponent = exponent - 15 + 127
        result = (sign << 31) | (UInt32(exponent) << 23) | (mantissa << 13)
    }
    
    return Float(bitPattern: result)
}

// MARK: - 渲染常量

public struct GaussianSplatConstants {
    /// 每个高斯点的字节大小
    public static let pointSize = MemoryLayout<GaussianPoint>.stride
    
    /// 最大支持的高斯点数量
    public static let maxPointCount = 10_000_000
    
    /// 默认批次大小
    public static let batchSize = 65_536
    
    /// 排序线程组大小
    public static let sortThreadgroupSize = 256
    
    /// 视锥剔除阈值
    public static let frustumCullThreshold: Float = 0.001
    
    /// Alpha 混合阈值
    public static let alphaThreshold: Float = 1.0 / 255.0
}

// MARK: - 相机参数

public struct CameraUniforms {
    /// 视图矩阵
    public var viewMatrix: simd_float4x4
    
    /// 投影矩阵
    public var projectionMatrix: simd_float4x4
    
    /// 视图投影矩阵
    public var viewProjectionMatrix: simd_float4x4
    
    /// 相机位置 (世界空间)
    public var cameraPosition: SIMD3<Float>
    
    /// 屏幕尺寸
    public var screenSize: SIMD2<Float>
    
    /// 近平面
    public var nearPlane: Float
    
    /// 远平面
    public var farPlane: Float
    
    /// 视场角 (弧度)
    public var fov: Float
    
    public init(
        viewMatrix: simd_float4x4 = matrix_identity_float4x4,
        projectionMatrix: simd_float4x4 = matrix_identity_float4x4,
        cameraPosition: SIMD3<Float> = SIMD3<Float>(0, 0, 5),
        screenSize: SIMD2<Float> = SIMD2<Float>(1920, 1080),
        nearPlane: Float = 0.1,
        farPlane: Float = 1000.0,
        fov: Float = Float.pi / 4
    ) {
        self.viewMatrix = viewMatrix
        self.projectionMatrix = projectionMatrix
        self.viewProjectionMatrix = projectionMatrix * viewMatrix
        self.cameraPosition = cameraPosition
        self.screenSize = screenSize
        self.nearPlane = nearPlane
        self.farPlane = farPlane
        self.fov = fov
    }
}

// MARK: - 排序键值

/// 用于 GPU 排序的深度键值
public struct SortKeyValue {
    /// 深度值 (归一化到 0-1)
    public var depth: UInt32
    
    /// 高斯点索引
    public var index: UInt32
    
    public init(depth: Float, index: UInt32) {
        // 将深度值转换为 UInt32 用于排序
        // 使用 32-bit 浮点位表示直接作为排序键
        self.depth = depth.bitPattern
        self.index = index
    }
}

// MARK: - 渲染配置

public struct RenderConfiguration {
    /// 背景颜色
    public var backgroundColor: SIMD4<Float>
    
    /// 是否启用视锥剔除
    public var enableFrustumCulling: Bool
    
    /// 是否启用深度排序
    public var enableDepthSorting: Bool
    
    /// 高斯缩放因子
    public var gaussianScale: Float
    
    /// 最大渲染点数
    public var maxRenderCount: Int
    
    /// 是否使用球谐光照
    public var useSphericalHarmonics: Bool
    
    public init(
        backgroundColor: SIMD4<Float> = SIMD4<Float>(0.15, 0.15, 0.15, 1.0),
        enableFrustumCulling: Bool = true,
        enableDepthSorting: Bool = true,
        gaussianScale: Float = 1.0,
        maxRenderCount: Int = 1_000_000,
        useSphericalHarmonics: Bool = true
    ) {
        self.backgroundColor = backgroundColor
        self.enableFrustumCulling = enableFrustumCulling
        self.enableDepthSorting = enableDepthSorting
        self.gaussianScale = gaussianScale
        self.maxRenderCount = maxRenderCount
        self.useSphericalHarmonics = useSphericalHarmonics
    }
}

// MARK: - PLY 文件解析结果

public struct PLYPointCloud {
    /// 点数据
    public var points: [GaussianPoint]
    
    /// 边界框最小点
    public var boundingBoxMin: SIMD3<Float>
    
    /// 边界框最大点
    public var boundingBoxMax: SIMD3<Float>
    
    /// 点数量
    public var count: Int { points.count }
    
    public init(points: [GaussianPoint] = []) {
        self.points = points
        self.boundingBoxMin = SIMD3<Float>(repeating: Float.infinity)
        self.boundingBoxMax = SIMD3<Float>(repeating: -Float.infinity)
        
        // 计算边界框
        for point in points {
            boundingBoxMin = min(boundingBoxMin, point.position)
            boundingBoxMax = max(boundingBoxMax, point.position)
        }
    }
}