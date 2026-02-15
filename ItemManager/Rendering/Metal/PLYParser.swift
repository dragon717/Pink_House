//
//  PLYParser.swift
//  ItemManager
//
//  PLY 文件解析器
//  支持 3D Gaussian Splatting 的 PLY 格式
//

import Foundation
import simd

// MARK: - PLY 解析器

public class PLYParser {
    
    /// 解析 PLY 文件
    public func parse(url: URL) throws -> PLYPointCloud {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }
    
    /// 解析 PLY 数据
    public func parse(data: Data) throws -> PLYPointCloud {
        guard let content = String(data: data, encoding: .utf8) else {
            throw PLYError.invalidEncoding
        }
        
        var lines = content.components(separatedBy: .newlines)
        
        // 解析头部
        let header = try parseHeader(lines: &lines)
        
        // 解析数据
        let points = try parseData(lines: lines, header: header)
        
        return PLYPointCloud(points: points)
    }
    
    /// 解析二进制 PLY 文件 (更高效)
    public func parseBinary(url: URL) throws -> PLYPointCloud {
        let data = try Data(contentsOf: url)
        
        // 找到头部结束位置
        guard let headerEndRange = data.range(of: Data("end_header\n".utf8)) ??
                                    data.range(of: Data("end_header\r\n".utf8)) else {
            throw PLYError.invalidHeader
        }
        
        let headerData = data.subdata(in: 0..<headerEndRange.upperBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw PLYError.invalidEncoding
        }
        
        var lines = headerString.components(separatedBy: .newlines)
        let header = try parseHeader(lines: &lines)
        
        // 解析二进制数据
        let bodyData = data.subdata(in: headerEndRange.upperBound..<data.count)
        let points = try parseBinaryData(data: bodyData, header: header)
        
        return PLYPointCloud(points: points)
    }
    
    // MARK: - 私有方法
    
    private func parseHeader(lines: inout [String]) throws -> PLYHeader {
        var header = PLYHeader()
        var inHeader = false
        var lineIndex = 0
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed == "ply" {
                inHeader = true
                continue
            }
            
            if !inHeader { continue }
            
            if trimmed == "end_header" {
                lineIndex = index + 1
                break
            }
            
            let parts = trimmed.components(separatedBy: .whitespaces)
            guard parts.count >= 2 else { continue }
            
            switch parts[0] {
            case "format":
                header.format = parts[1]
                header.version = parts.count > 2 ? parts[2] : "1.0"
                
            case "element":
                if parts[1] == "vertex" && parts.count >= 3 {
                    header.vertexCount = Int(parts[2]) ?? 0
                }
                
            case "property":
                if parts.count >= 3 {
                    let property = PLYProperty(
                        type: parts[1],
                        name: parts[2]
                    )
                    header.properties.append(property)
                }
                
            default:
                break
            }
        }
        
        // 移除头部行，保留数据行
        lines = Array(lines[lineIndex...])
        
        return header
    }
    
    private func parseData(lines: [String], header: PLYHeader) throws -> [GaussianPoint] {
        var points: [GaussianPoint] = []
        points.reserveCapacity(header.vertexCount)
        
        var parsedCount = 0
        
        for line in lines {
            if parsedCount >= header.vertexCount { break }
            
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            let values = trimmed.components(separatedBy: .whitespaces)
            
            if let point = parsePoint(values: values, properties: header.properties) {
                points.append(point)
                parsedCount += 1
            }
        }
        
        return points
    }
    
    private func parseBinaryData(data: Data, header: PLYHeader) throws -> [GaussianPoint] {
        var points: [GaussianPoint] = []
        points.reserveCapacity(header.vertexCount)
        
        let vertexSize = calculateVertexSize(properties: header.properties)
        
        for i in 0..<header.vertexCount {
            let offset = i * vertexSize
            guard offset + vertexSize <= data.count else { break }
            
            let vertexData = data.subdata(in: offset..<(offset + vertexSize))
            if let point = parseBinaryPoint(data: vertexData, properties: header.properties) {
                points.append(point)
            }
        }
        
        return points
    }
    
    private func parsePoint(values: [String], properties: [PLYProperty]) -> GaussianPoint? {
        guard values.count >= properties.count else { return nil }
        
        var point = GaussianPoint()
        var shCoefficients: [Float] = Array(repeating: 0, count: 16)
        
        for (index, property) in properties.enumerated() {
            guard index < values.count else { continue }
            
            let value = Float(values[index]) ?? 0
            
            switch property.name {
            case "x":
                point.position.x = value
            case "y":
                point.position.y = value
            case "z":
                point.position.z = value
                
            case "nx", "normal_x":
                // 忽略法线
                break
            case "ny", "normal_y":
                break
            case "nz", "normal_z":
                break
                
            case "f_dc_0":
                shCoefficients[0] = value
            case "f_dc_1":
                shCoefficients[1] = value
            case "f_dc_2":
                shCoefficients[2] = value
                
            case let name where name.hasPrefix("f_rest_"):
                // 解析球谐系数
                if let shIndex = Int(name.dropFirst(7)) {
                    let targetIndex = 3 + shIndex
                    if targetIndex < 16 {
                        shCoefficients[targetIndex] = value
                    }
                }
                
            case "opacity":
                // 应用 sigmoid 逆变换
                point.opacity = sigmoid(value)
                
            case "scale_0":
                point.scale.x = exp(value)
            case "scale_1":
                point.scale.y = exp(value)
            case "scale_2":
                point.scale.z = exp(value)
                
            case "rot_0":
                point.rotation.x = value
            case "rot_1":
                point.rotation.y = value
            case "rot_2":
                point.rotation.z = value
            case "rot_3":
                point.rotation.w = value
                
            default:
                break
            }
        }
        
        // 归一化旋转四元数
        let length = sqrt(
            point.rotation.x * point.rotation.x +
            point.rotation.y * point.rotation.y +
            point.rotation.z * point.rotation.z +
            point.rotation.w * point.rotation.w
        )
        if length > 0 {
            point.rotation.x /= length
            point.rotation.y /= length
            point.rotation.z /= length
            point.rotation.w /= length
        }
        
        // 设置球谐系数
        point = GaussianPoint(
            position: point.position,
            rotation: point.rotation,
            scale: point.scale,
            opacity: point.opacity,
            shCoefficients: shCoefficients
        )
        
        return point
    }
    
    private func parseBinaryPoint(data: Data, properties: [PLYProperty]) -> GaussianPoint? {
        var point = GaussianPoint()
        var shCoefficients: [Float] = Array(repeating: 0, count: 16)
        
        var offset = 0
        
        for property in properties {
            let size = propertySize(property.type)
            guard offset + size <= data.count else { break }
            
            let valueData = data.subdata(in: offset..<(offset + size))
            let value: Float
            
            switch property.type {
            case "float", "float32":
                value = valueData.withUnsafeBytes { $0.load(as: Float.self) }
            case "double", "float64":
                let doubleValue = valueData.withUnsafeBytes { $0.load(as: Double.self) }
                value = Float(doubleValue)
            case "uchar", "uint8":
                let intValue = valueData.withUnsafeBytes { $0.load(as: UInt8.self) }
                value = Float(intValue) / 255.0
            default:
                value = 0
            }
            
            offset += size
            
            // 解析属性值 (与 ASCII 版本相同)
            switch property.name {
            case "x":
                point.position.x = value
            case "y":
                point.position.y = value
            case "z":
                point.position.z = value
            case "f_dc_0":
                shCoefficients[0] = value
            case "f_dc_1":
                shCoefficients[1] = value
            case "f_dc_2":
                shCoefficients[2] = value
            case let name where name.hasPrefix("f_rest_"):
                if let shIndex = Int(name.dropFirst(7)) {
                    let targetIndex = 3 + shIndex
                    if targetIndex < 16 {
                        shCoefficients[targetIndex] = value
                    }
                }
            case "opacity":
                point.opacity = sigmoid(value)
            case "scale_0":
                point.scale.x = exp(value)
            case "scale_1":
                point.scale.y = exp(value)
            case "scale_2":
                point.scale.z = exp(value)
            case "rot_0":
                point.rotation.x = value
            case "rot_1":
                point.rotation.y = value
            case "rot_2":
                point.rotation.z = value
            case "rot_3":
                point.rotation.w = value
            default:
                break
            }
        }
        
        // 归一化旋转四元数
        let length = sqrt(
            point.rotation.x * point.rotation.x +
            point.rotation.y * point.rotation.y +
            point.rotation.z * point.rotation.z +
            point.rotation.w * point.rotation.w
        )
        if length > 0 {
            point.rotation.x /= length
            point.rotation.y /= length
            point.rotation.z /= length
            point.rotation.w /= length
        }
        
        point = GaussianPoint(
            position: point.position,
            rotation: point.rotation,
            scale: point.scale,
            opacity: point.opacity,
            shCoefficients: shCoefficients
        )
        
        return point
    }
    
    private func calculateVertexSize(properties: [PLYProperty]) -> Int {
        return properties.reduce(0) { sum, property in
            sum + propertySize(property.type)
        }
    }
    
    private func propertySize(_ type: String) -> Int {
        switch type {
        case "char", "int8": return 1
        case "uchar", "uint8": return 1
        case "short", "int16": return 2
        case "ushort", "uint16": return 2
        case "int", "int32": return 4
        case "uint", "uint32": return 4
        case "float", "float32": return 4
        case "double", "float64": return 8
        default: return 4
        }
    }
    
    private func sigmoid(_ x: Float) -> Float {
        return 1.0 / (1.0 + exp(-x))
    }
}

// MARK: - 辅助类型

struct PLYHeader {
    var format: String = "ascii"
    var version: String = "1.0"
    var vertexCount: Int = 0
    var properties: [PLYProperty] = []
}

struct PLYProperty {
    let type: String
    let name: String
}

public enum PLYError: Error {
    case invalidEncoding
    case invalidHeader
    case unsupportedFormat
    case parseError(String)
}
