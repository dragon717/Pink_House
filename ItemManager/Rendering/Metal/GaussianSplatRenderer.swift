//
//  GaussianSplatRenderer.swift
//  ItemManager
//
//  3D Gaussian Splatting Metal 渲染器
//  管理渲染管线、Buffer 和排序
//

import Foundation
import Metal
import MetalKit
import simd
import Combine

// MARK: - 渲染器协议

public protocol GaussianSplatRendererDelegate: AnyObject {
    func renderer(_ renderer: GaussianSplatRenderer, didUpdateFrameTime frameTime: Double)
    func renderer(_ renderer: GaussianSplatRenderer, didEncounterError error: Error)
}

// MARK: - 主渲染器

public class GaussianSplatRenderer: NSObject, MTKViewDelegate {
    
    // MARK: - 属性
    
    /// Metal 设备
    public let device: MTLDevice
    
    /// 命令队列
    private let commandQueue: MTLCommandQueue
    
    /// 渲染管线状态
    private var renderPipelineState: MTLRenderPipelineState?
    
    /// 计算管线状态
    private var preprocessPipelineState: MTLComputePipelineState?
    private var sortPipelineState: MTLComputePipelineState?
    
    /// 深度模板状态
    private var depthStencilState: MTLDepthStencilState?
    
    /// Buffer
    private var pointBuffer: MTLBuffer?
    private var sortKeyBuffer: MTLBuffer?
    private var cameraUniformsBuffer: MTLBuffer?
    private var visibleCountBuffer: MTLBuffer?
    
    /// 当前高斯点数量
    private var pointCount: Int = 0
    
    /// 相机参数
    private var cameraUniforms = CameraUniforms()
    
    /// 渲染配置
    public var configuration = RenderConfiguration()
    
    /// 委托
    public weak var delegate: GaussianSplatRendererDelegate?
    
    /// 渲染统计
    private var frameCount: Int = 0
    private var lastFrameTime: CFTimeInterval = 0
    private var currentFrameTime: Double = 0
    
    /// 排序状态
    private var needsSorting: Bool = true
    private var lastSortFrame: Int = -100 // 强制第一帧排序
    
    /// 渲染尺寸
    private var viewportSize: CGSize = .zero
    
    // MARK: - 初始化
    
    public init?(device: MTLDevice) {
        self.device = device
        
        guard let commandQueue = device.makeCommandQueue() else {
            print("[GaussianSplatRenderer] Failed to create command queue")
            return nil
        }
        self.commandQueue = commandQueue
        
        super.init()
        
        // 初始化渲染管线
        do {
            try setupPipelines()
            try setupBuffers()
        } catch {
            print("[GaussianSplatRenderer] Setup error: \(error)")
            return nil
        }
    }
    
    // MARK: - 设置
    
    private func setupPipelines() throws {
        // 加载 shader
        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.shaderCompilationFailed
        }
        
        // Render Pipeline
        let vertexFunction = library.makeFunction(name: "gaussianVertex")
        let fragmentFunction = library.makeFunction(name: "gaussianFragment")
        
        let renderDescriptor = MTLRenderPipelineDescriptor()
        renderDescriptor.vertexFunction = vertexFunction
        renderDescriptor.fragmentFunction = fragmentFunction
        renderDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        renderDescriptor.colorAttachments[0].isBlendingEnabled = true
        renderDescriptor.colorAttachments[0].rgbBlendOperation = .add
        renderDescriptor.colorAttachments[0].alphaBlendOperation = .add
        renderDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        renderDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        renderDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        renderDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        renderDescriptor.depthAttachmentPixelFormat = .depth32Float
        
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: renderDescriptor)
        } catch {
            throw RendererError.pipelineCreationFailed(error)
        }
        
        // Compute Pipelines
        if let preprocessFunction = library.makeFunction(name: "preprocessGaussians") {
            preprocessPipelineState = try device.makeComputePipelineState(function: preprocessFunction)
        }
        
        if let sortFunction = library.makeFunction(name: "bitonicSortStep") {
            sortPipelineState = try device.makeComputePipelineState(function: sortFunction)
        }
        
        // Depth Stencil State
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = false // 3DGS 不需要深度写入
        depthStencilState = device.makeDepthStencilState(descriptor: depthDescriptor)
    }
    
    private func setupBuffers() throws {
        // 相机 Uniforms Buffer
        cameraUniformsBuffer = device.makeBuffer(
            length: MemoryLayout<CameraUniforms>.stride,
            options: .storageModeShared
        )
        
        // 可见性计数 Buffer
        visibleCountBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: .storageModePrivate
        )
    }
    
    // MARK: - 数据加载
    
    /// 加载 PLY 点云数据
    public func loadPointCloud(_ pointCloud: PLYPointCloud) {
        let points = pointCloud.points
        pointCount = min(points.count, GaussianSplatConstants.maxPointCount)
        
        guard pointCount > 0 else { return }
        
        // 创建点数据 Buffer
        let pointDataSize = pointCount * GaussianSplatConstants.pointSize
        pointBuffer = device.makeBuffer(
            bytes: points,
            length: pointDataSize,
            options: .storageModeShared
        )
        
        // 创建排序键值 Buffer
        let sortKeySize = pointCount * MemoryLayout<SortKeyValue>.stride
        sortKeyBuffer = device.makeBuffer(
            length: sortKeySize,
            options: .storageModePrivate
        )
        
        needsSorting = true
        
        print("[GaussianSplatRenderer] Loaded \(pointCount) points")
    }
    
    /// 从 PLY 文件加载
    public func loadPLYFile(url: URL) throws {
        let parser = PLYParser()
        let pointCloud = try parser.parse(url: url)
        loadPointCloud(pointCloud)
    }
    
    /// 清空数据
    public func clear() {
        pointCount = 0
        pointBuffer = nil
        sortKeyBuffer = nil
        needsSorting = false
    }
    
    // MARK: - 相机控制
    
    /// 更新相机参数
    public func updateCamera(
        position: SIMD3<Float>,
        target: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        up: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
        fov: Float = Float.pi / 4,
        nearPlane: Float = 0.1,
        farPlane: Float = 1000.0
    ) {
        // 构建视图矩阵
        let forward = normalize(target - position)
        let right = normalize(cross(forward, up))
        let cameraUp = cross(right, forward)
        
        var viewMatrix = simd_float4x4(
            SIMD4<Float>(right.x, cameraUp.x, -forward.x, 0),
            SIMD4<Float>(right.y, cameraUp.y, -forward.y, 0),
            SIMD4<Float>(right.z, cameraUp.z, -forward.z, 0),
            SIMD4<Float>(-dot(right, position), -dot(cameraUp, position), dot(forward, position), 1)
        )
        
        // 构建投影矩阵
        let aspect = Float(viewportSize.width / max(viewportSize.height, 1))
        let projectionMatrix = perspectiveMatrix(fov: fov, aspect: aspect, near: nearPlane, far: farPlane)
        
        cameraUniforms = CameraUniforms(
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            cameraPosition: position,
            screenSize: SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height)),
            nearPlane: nearPlane,
            farPlane: farPlane,
            fov: fov
        )
        
        // 更新 Buffer
        if let buffer = cameraUniformsBuffer {
            memcpy(buffer.contents(), &cameraUniforms, MemoryLayout<CameraUniforms>.stride)
        }
        
        needsSorting = true
    }
    
    /// 构建透视投影矩阵
    private func perspectiveMatrix(fov: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let f = 1.0 / tan(fov / 2.0)
        let nf = 1.0 / (near - far)
        
        return simd_float4x4(
            SIMD4<Float>(f / aspect, 0, 0, 0),
            SIMD4<Float>(0, f, 0, 0),
            SIMD4<Float>(0, 0, (far + near) * nf, -1),
            SIMD4<Float>(0, 0, 2 * far * near * nf, 0)
        )
    }
    
    // MARK: - MTKViewDelegate
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
        needsSorting = true
    }
    
    public func draw(in view: MTKView) {
        guard pointCount > 0,
              let pointBuffer = pointBuffer,
              let sortKeyBuffer = sortKeyBuffer,
              let renderPipelineState = renderPipelineState,
              let cameraUniformsBuffer = cameraUniformsBuffer else {
            return
        }
        
        let startTime = CACurrentMediaTime()
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            return
        }
        
        // MARK: Compute Pass - 预处理和排序
        
        if configuration.enableDepthSorting && needsSorting {
            performSorting(commandBuffer: commandBuffer)
        }
        
        // MARK: Render Pass
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        renderEncoder?.setRenderPipelineState(renderPipelineState)
        renderEncoder?.setDepthStencilState(depthStencilState)
        
        // 设置 Buffer
        renderEncoder?.setVertexBuffer(pointBuffer, offset: 0, index: 0)
        renderEncoder?.setVertexBuffer(sortKeyBuffer, offset: 0, index: 1)
        renderEncoder?.setVertexBuffer(cameraUniformsBuffer, offset: 0, index: 2)
        
        var gaussianScale = configuration.gaussianScale
        renderEncoder?.setVertexBytes(&gaussianScale, length: MemoryLayout<Float>.stride, index: 3)
        
        // 绘制 - 每个高斯点是一个四边形 (4个顶点，triangle strip)
        let renderCount = min(pointCount, configuration.maxRenderCount)
        renderEncoder?.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4,
            instanceCount: renderCount
        )
        
        renderEncoder?.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        // 更新统计
        frameCount += 1
        currentFrameTime = CACurrentMediaTime() - startTime
        
        if frameCount % 60 == 0 {
            delegate?.renderer(self, didUpdateFrameTime: currentFrameTime)
        }
    }
    
    // MARK: - 排序
    
    private func performSorting(commandBuffer: MTLCommandBuffer) {
        guard let preprocessPipeline = preprocessPipelineState,
              let sortPipeline = sortPipelineState,
              let visibleCountBuffer = visibleCountBuffer else {
            return
        }
        
        var pointCountUInt = UInt32(pointCount)
        
        // 1. 预处理 - 计算深度值
        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.setComputePipelineState(preprocessPipeline)
            computeEncoder.setBuffer(pointBuffer, offset: 0, index: 0)
            computeEncoder.setBuffer(sortKeyBuffer, offset: 0, index: 1)
            computeEncoder.setBuffer(visibleCountBuffer, offset: 0, index: 2)
            computeEncoder.setBuffer(cameraUniformsBuffer, offset: 0, index: 3)
            computeEncoder.setBytes(&pointCountUInt, length: MemoryLayout<UInt32>.stride, index: 4)
            
            let threadsPerGroup = MTLSize(width: GaussianSplatConstants.sortThreadgroupSize, height: 1, depth: 1)
            let numGroups = (pointCount + threadsPerGroup.width - 1) / threadsPerGroup.width
            let threadgroups = MTLSize(width: numGroups, height: 1, depth: 1)
            
            computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerGroup)
            computeEncoder.endEncoding()
        }
        
        // 2. Bitonic 排序
        let n = UInt32(pointCount)
        var stage: UInt32 = 1
        while stage <= n {
            var step: UInt32 = stage
            while step >= 1 {
                if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
                    computeEncoder.setComputePipelineState(sortPipeline)
                    computeEncoder.setBuffer(sortKeyBuffer, offset: 0, index: 0)
                    computeEncoder.setBytes(&stage, length: MemoryLayout<UInt32>.stride, index: 1)
                    computeEncoder.setBytes(&step, length: MemoryLayout<UInt32>.stride, index: 2)
                    computeEncoder.setBytes(&pointCountUInt, length: MemoryLayout<UInt32>.stride, index: 3)
                    
                    let threadsPerGroup = MTLSize(width: GaussianSplatConstants.sortThreadgroupSize, height: 1, depth: 1)
                    let numGroups = (Int(n) + threadsPerGroup.width - 1) / threadsPerGroup.width
                    let threadgroups = MTLSize(width: numGroups, height: 1, depth: 1)
                    
                    computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerGroup)
                    computeEncoder.endEncoding()
                }
                step /= 2
            }
            stage *= 2
        }
        
        needsSorting = false
        lastSortFrame = frameCount
    }
    
    // MARK: - 外部渲染接口
    
    /// 渲染到指定的 render pass descriptor（用于场景集成）
    public func render(to renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        guard pointCount > 0,
              let renderPipelineState = renderPipelineState,
              let depthStencilState = depthStencilState else {
            return
        }
        
        // 预处理和排序
        if configuration.enableDepthSorting && needsSorting {
            performSorting(commandBuffer: commandBuffer)
        }
        
        // 渲染
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        renderEncoder?.setRenderPipelineState(renderPipelineState)
        renderEncoder?.setDepthStencilState(depthStencilState)
        
        // 设置 Buffer
        renderEncoder?.setVertexBuffer(pointBuffer, offset: 0, index: 0)
        renderEncoder?.setVertexBuffer(sortKeyBuffer, offset: 0, index: 1)
        renderEncoder?.setVertexBuffer(cameraUniformsBuffer, offset: 0, index: 2)
        
        var gaussianScale = configuration.gaussianScale
        renderEncoder?.setVertexBytes(&gaussianScale, length: MemoryLayout<Float>.stride, index: 3)
        
        // 绘制
        let renderCount = min(pointCount, configuration.maxRenderCount)
        renderEncoder?.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4,
            instanceCount: renderCount
        )
        
        renderEncoder?.endEncoding()
        
        // 更新统计
        frameCount += 1
    }
    
    // MARK: - 工具方法
    
    /// 获取当前 FPS
    public var currentFPS: Double {
        return currentFrameTime > 0 ? 1.0 / currentFrameTime : 0
    }
    
    /// 获取渲染统计信息
    public var renderStats: RenderStats {
        return RenderStats(
            frameTime: currentFrameTime,
            fps: currentFPS,
            pointCount: pointCount,
            renderedPoints: min(pointCount, configuration.maxRenderCount)
        )
    }
}

// MARK: - 错误类型

public enum RendererError: Error {
    case shaderCompilationFailed
    case pipelineCreationFailed(Error)
    case bufferCreationFailed
    case invalidPLYFile
}

// MARK: - 渲染统计

public struct RenderStats {
    public let frameTime: Double
    public let fps: Double
    public let pointCount: Int
    public let renderedPoints: Int
}
