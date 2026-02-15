//
//  GaussianSplatShaders.metal
//  ItemManager
//
//  3D Gaussian Splatting Metal Shaders
//  包含 Compute Shader 和 Render Shader
//

#include <metal_stdlib>
using namespace metal;

// MARK: - 数据结构定义

/// 高斯点数据结构 (与 Swift 对齐)
struct GaussianPoint {
    float3 position;      // 12 bytes
    float4 rotation;      // 16 bytes (四元数)
    float3 scale;         // 12 bytes
    float opacity;        // 4 bytes
    half   sh[16];        // 32 bytes (16个 half 精度球谐系数)
};                      // 总计: 76 bytes，对齐到 80 bytes

/// 相机参数
struct CameraUniforms {
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float4x4 viewProjectionMatrix;
    float3   cameraPosition;
    float2   screenSize;
    float    nearPlane;
    float    farPlane;
    float    fov;
};

/// 排序键值
struct SortKeyValue {
    uint depth;
    uint index;
};

/// 顶点输出
struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float  opacity;
};

// MARK: - 工具函数

/// 四元数乘法
float4 quaternionMultiply(float4 q1, float4 q2) {
    float4 result;
    result.x = q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y;
    result.y = q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x;
    result.z = q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w;
    result.w = q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z;
    return result;
}

/// 四元数共轭
float4 quaternionConjugate(float4 q) {
    return float4(-q.x, -q.y, -q.z, q.w);
}

/// 用四元数旋转向量
float3 rotateVector(float3 v, float4 q) {
    float4 qv = float4(v, 0.0);
    float4 qConj = quaternionConjugate(q);
    float4 result = quaternionMultiply(quaternionMultiply(q, qv), qConj);
    return result.xyz;
}

/// 计算 3D 高斯协方差矩阵 (3x3)
/// 返回矩阵的逆 (用于计算椭圆)
float3x3 computeCovariance3D(float3 scale, float4 rotation) {
    // 构建缩放矩阵
    float3x3 S = float3x3(
        scale.x, 0.0, 0.0,
        0.0, scale.y, 0.0,
        0.0, 0.0, scale.z
    );
    
    // 构建旋转矩阵 (从四元数)
    float r = rotation.x;
    float x = rotation.y;
    float y = rotation.z;
    float z = rotation.w;
    
    float3x3 R = float3x3(
        1.0 - 2.0 * (y*y + z*z), 2.0 * (x*y - r*z), 2.0 * (x*z + r*y),
        2.0 * (x*y + r*z), 1.0 - 2.0 * (x*x + z*z), 2.0 * (y*z - r*x),
        2.0 * (x*z - r*y), 2.0 * (y*z + r*x), 1.0 - 2.0 * (x*x + y*y)
    );
    
    // 协方差矩阵 = R * S * S^T * R^T
    float3x3 M = R * S;
    float3x3 Sigma = M * transpose(M);
    
    return Sigma;
}

/// 计算 2D 投影协方差矩阵
float2x2 computeCovariance2D(float3 mean, float3x3 cov3D, float4x4 viewMatrix, float4x4 projMatrix, float2 screenSize) {
    // 视图空间位置
    float4 viewPos = viewMatrix * float4(mean, 1.0);
    
    // 计算 Jacobian 矩阵 (透视投影的线性近似)
    float focalX = projMatrix[0][0] * screenSize.x * 0.5;
    float focalY = projMatrix[1][1] * screenSize.y * 0.5;
    
    float z = viewPos.z;
    float z2 = z * z;
    
    float3x3 J = float3x3(
        focalX / z, 0.0, -(focalX * viewPos.x) / z2,
        0.0, focalY / z, -(focalY * viewPos.y) / z2,
        0.0, 0.0, 0.0
    );
    
    // 视图空间变换
    float3x3 W = float3x3(
        viewMatrix[0][0], viewMatrix[0][1], viewMatrix[0][2],
        viewMatrix[1][0], viewMatrix[1][1], viewMatrix[1][2],
        viewMatrix[2][0], viewMatrix[2][1], viewMatrix[2][2]
    );
    
    float3x3 T = J * W;
    float3x3 cov2D = T * cov3D * transpose(T);
    
    // 添加低通滤波避免数值问题
    cov2D[0][0] += 0.3;
    cov2D[1][1] += 0.3;
    
    return float2x2(
        cov2D[0][0], cov2D[0][1],
        cov2D[1][0], cov2D[1][1]
    );
}

/// 计算球谐系数颜色
float3 computeSHColor(device const GaussianPoint& point, float3 direction) {
    // 归一化方向
    float3 dir = normalize(direction);
    
    // 第0阶 (常数项)
    float3 color = float3(
        float(point.sh[0]),
        float(point.sh[1]),
        float(point.sh[2])
    );
    
    // 第1阶 (线性项)
    float x = dir.x;
    float y = dir.y;
    float z = dir.z;
    
    color.r += float(point.sh[3]) * x + float(point.sh[4]) * y + float(point.sh[5]) * z;
    color.g += float(point.sh[6]) * x + float(point.sh[7]) * y + float(point.sh[8]) * z;
    color.b += float(point.sh[9]) * x + float(point.sh[10]) * y + float(point.sh[11]) * z;
    
    // 第2阶 (二次项) - 简化处理
    // ...
    
    // 应用 sigmoid 激活
    color = 1.0 / (1.0 + exp(-color));
    
    return color;
}

// MARK: - Compute Shader: 预处理

/// 计算深度值和可见性
kernel void preprocessGaussians(
    device const GaussianPoint* points [[buffer(0)]],
    device SortKeyValue* sortKeys [[buffer(1)]],
    device atomic_uint* visibleCount [[buffer(2)]],
    constant CameraUniforms& camera [[buffer(3)]],
    constant uint& pointCount [[buffer(4)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= pointCount) return;
    
    GaussianPoint point = points[gid];
    
    // 变换到视图空间
    float4 viewPos = camera.viewMatrix * float4(point.position, 1.0);
    
    // 视锥剔除: 检查是否在相机前方且在视锥内
    if (viewPos.z < camera.nearPlane || viewPos.z > camera.farPlane) {
        sortKeys[gid].depth = 0xFFFFFFFF; // 标记为不可见
        sortKeys[gid].index = gid;
        return;
    }
    
    // 简单的视锥测试
    float4 clipPos = camera.projectionMatrix * viewPos;
    float3 ndc = clipPos.xyz / clipPos.w;
    
    if (any(ndc < float3(-1.2)) || any(ndc > float3(1.2))) {
        sortKeys[gid].depth = 0xFFFFFFFF;
        sortKeys[gid].index = gid;
        return;
    }
    
    // 计算深度值 (用于排序)
    // 使用视图空间 Z 值，反转以便从远到近排序
    float depthNorm = 1.0 - (viewPos.z - camera.nearPlane) / (camera.farPlane - camera.nearPlane);
    uint depthKey = as_type<uint>(depthNorm);
    
    sortKeys[gid].depth = depthKey;
    sortKeys[gid].index = gid;
    
    atomic_fetch_add_explicit(visibleCount, 1, memory_order_relaxed);
}

// MARK: - Compute Shader: Bitonic Sort

/// Bitonic 排序的比较-交换操作
kernel void bitonicSortStep(
    device SortKeyValue* data [[buffer(0)]],
    constant uint& stage [[buffer(1)]],
    constant uint& step [[buffer(2)]],
    constant uint& count [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    
    uint pairDistance = 1 << (stage - step);
    uint blockWidth = pairDistance * 2;
    
    uint leftId = (gid / pairDistance) * blockWidth + (gid % pairDistance);
    uint rightId = leftId + pairDistance;
    
    if (rightId >= count) return;
    
    SortKeyValue left = data[leftId];
    SortKeyValue right = data[rightId];
    
    // 确定排序方向 (升序或降序)
    uint sameDirectionBlockWidth = 1 << stage;
    bool ascending = ((leftId / sameDirectionBlockWidth) % 2) == 0;
    
    // 比较并交换
    bool shouldSwap = ascending ? (left.depth > right.depth) : (left.depth < right.depth);
    
    if (shouldSwap) {
        data[leftId] = right;
        data[rightId] = left;
    }
}

// MARK: - Vertex Shader

vertex VertexOut gaussianVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device const GaussianPoint* points [[buffer(0)]],
    device const SortKeyValue* sortedIndices [[buffer(1)]],
    constant CameraUniforms& camera [[buffer(2)]],
    constant float& gaussianScale [[buffer(3)]]
) {
    VertexOut out;
    
    // 获取排序后的点索引
    uint pointIndex = sortedIndices[instanceID].index;
    
    // 检查是否有效
    if (sortedIndices[instanceID].depth == 0xFFFFFFFF) {
        out.position = float4(0.0, 0.0, 0.0, 0.0);
        out.uv = float2(0.0);
        out.color = float4(0.0);
        out.opacity = 0.0;
        return out;
    }
    
    device const GaussianPoint& point = points[pointIndex];
    
    // 顶点布局 (四边形)
    float2 quadVertices[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    
    float2 quadUVs[4] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(1.0, 1.0)
    };
    
    float2 quadPos = quadVertices[vertexID];
    float2 uv = quadUVs[vertexID];
    
    // 计算 3D 协方差
    float3x3 cov3D = computeCovariance3D(point.scale * gaussianScale, point.rotation);
    
    // 计算 2D 投影协方差
    float2x2 cov2D = computeCovariance2D(
        point.position, cov3D,
        camera.viewMatrix, camera.projectionMatrix, camera.screenSize
    );
    
    // 计算 2D 高斯的逆协方差
    float det = cov2D[0][0] * cov2D[1][1] - cov2D[0][1] * cov2D[1][0];
    if (abs(det) < 1e-6) {
        out.position = float4(0.0, 0.0, 0.0, 0.0);
        out.opacity = 0.0;
        return out;
    }
    
    float2x2 invCov = float2x2(
        cov2D[1][1] / det, -cov2D[0][1] / det,
        -cov2D[1][0] / det, cov2D[0][0] / det
    );
    
    // 计算投影中心
    float4 viewPos = camera.viewMatrix * float4(point.position, 1.0);
    float4 clipPos = camera.projectionMatrix * viewPos;
    float2 screenCenter = (clipPos.xy / clipPos.w) * 0.5 + 0.5;
    screenCenter.y = 1.0 - screenCenter.y; // 翻转 Y
    screenCenter *= camera.screenSize;
    
    // 计算椭圆半径 (3个标准差覆盖99%区域)
    float radius = 3.0 * sqrt(max(cov2D[0][0], cov2D[1][1]));
    radius = clamp(radius, 1.0, 100.0);
    
    // 变换顶点到屏幕空间
    float2 screenPos = screenCenter + quadPos * radius;
    
    // 转换回 NDC
    float2 ndcPos = (screenPos / camera.screenSize) * 2.0 - 1.0;
    ndcPos.y = -ndcPos.y;
    
    out.position = float4(ndcPos, clipPos.z / clipPos.w, 1.0);
    out.uv = uv * 2.0 - 1.0; // 映射到 [-1, 1]
    
    // 计算颜色 (使用球谐系数)
    float3 viewDir = normalize(point.position - camera.cameraPosition);
    float3 color = computeSHColor(point, viewDir);
    
    out.color = float4(color, 1.0);
    out.opacity = point.opacity;
    
    return out;
}

// MARK: - Fragment Shader

fragment float4 gaussianFragment(
    VertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]]
) {
    // 计算 2D 高斯权重
    float2 d = in.uv;
    float power = -0.5 * dot(d, d);
    
    // 裁剪过小的值
    if (power < -4.0) {
        discard_fragment();
    }
    
    // 计算 Alpha
    float alpha = in.opacity * exp(power);
    
    // Alpha 阈值测试
    if (alpha < 0.01) {
        discard_fragment();
    }
    
    // 输出颜色 (预乘 Alpha)
    float3 color = in.color.rgb;
    return float4(color * alpha, alpha);
}

// MARK: - 简化版 Fragment Shader (用于性能模式)

fragment float4 gaussianFragmentFast(
    VertexOut in [[stage_in]]
) {
    float2 d = in.uv;
    float dist2 = dot(d, d);
    
    if (dist2 > 4.0) {
        discard_fragment();
    }
    
    float alpha = in.opacity * exp(-0.5 * dist2);
    return float4(in.color.rgb * alpha, alpha);
}