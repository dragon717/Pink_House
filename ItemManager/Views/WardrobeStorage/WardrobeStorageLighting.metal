#include <metal_stdlib>
using namespace metal;

// A fixed light above each shelf. Positions/normals describe coarse planes, not
// reconstructed relief. Coordinates are registered to storage_cabinet_shelf.
[[ stitchable ]] half4 wardrobeFurnitureLight(float2 position, half4 color, float2 size, float part) {
    if (color.a <= 0.0001h) return color;
    float2 uv = position / max(size, float2(1));
    float3 rgb = float3(color.rgb / color.a);
    float3 illumination;
    if (part < 0.5) {
        float3 normal = float3(0, 0, 1);
        float3 point = float3(uv.x, uv.y, 0);
        bool interior = uv.x > 0.10 && uv.x < 0.90 && uv.y < 0.87;
        if (interior && uv.y > 0.705) {
            // Front edge of the horizontal shelf comes toward the viewer.
            normal = float3(0, -1, 0);
            point = float3(uv.x, 0.705, (uv.y - 0.705) * 2.4);
        } else if (interior && (uv.x < 0.153 || uv.x > 0.847)) {
            normal = float3(uv.x < 0.153 ? 1 : -1, 0, 0);
            point.z = abs(uv.x - (uv.x < 0.153 ? 0.153 : 0.847)) * 7;
        }
        float3 source = float3(clamp(uv.x, 0.20, 0.80), 0.035, 0.40);
        float3 direction = source - point;
        float distanceSquared = dot(direction, direction);
        float diffuse = max(0.0, dot(normal, normalize(direction)));
        float warm = diffuse / (1.0 + 2.0 * distanceSquared);
        // Front posts/trim remain separate from the recessed, warmer back wall.
        illumination = interior ? float3(0.19, 0.18, 0.22) + float3(0.79, 0.65, 0.46) * warm
                                : float3(0.48, 0.43, 0.43);
        // Occlusion at the vertical joins retains depth instead of flattening it.
        if (interior) {
            float side = min(abs(uv.x - 0.153), abs(uv.x - 0.847));
            illumination *= 0.84 + 0.16 * smoothstep(0.0, 0.035, side);
        }
    } else {
        float glow = exp(-pow((uv.x - 0.5) * 2.8, 2.0));
        illumination = float3(0.40, 0.36, 0.39) + float3(0.17, 0.13, 0.09) * glow;
    }
    return half4(half3(clamp(rgb * illumination, 0.0, 1.0)) * color.a, color.a);
}

[[ stitchable ]] half4 wardrobeItemLight(float2 position, half4 color, float2 size) {
    if (color.a <= 0.0001h) return color;
    float y = clamp(position.y / max(size.y, 1.0), 0.0, 1.0);
    float3 rgb = float3(color.rgb / color.a);
    // Subtle top lighting preserves white/black items and their chosen color.
    float3 light = mix(float3(1.00, 0.96, 0.90), float3(0.78, 0.77, 0.79), y);
    return half4(half3(clamp(rgb * light, 0.0, 1.0)) * color.a, color.a);
}
