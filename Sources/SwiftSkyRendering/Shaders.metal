// swiftSky shaders.
//
// A full-screen quad rendered as a triangle strip, filled black. Trivial by design — the point of
// FR-002a is that this path exists and is exercised, not that it draws anything interesting. A pass
// that merely cleared the surface would leave shader compilation, pipeline-state creation, geometry
// binding, and draw submission untested, which is exactly what this feature exists to prove works
// before any content depends on it.
//
// Vertex positions arrive in clip space, so a surface resize changes the viewport and nothing else.
// There is no resize-time geometry update to get wrong (research.md R11).

#include <metal_stdlib>
using namespace metal;

namespace swiftsky {

/// One corner of the full-screen quad. Mirrors `FullscreenQuad.Vertex` on the Swift side — the two
/// layouts must stay in step.
struct Vertex {
    float2 position;
};

struct RasterizerData {
    float4 position [[position]];
};

}  // namespace swiftsky

vertex swiftsky::RasterizerData swiftsky_quad_vertex(
    uint vertexID [[vertex_id]],
    const device swiftsky::Vertex *vertices [[buffer(0)]])
{
    swiftsky::RasterizerData out;
    out.position = float4(vertices[vertexID].position, 0.0, 1.0);
    return out;
}

/// Opaque black in the surface's sRGB space — FR-002 and FR-002c.
///
/// The colour is a rendering-layer concern and is deliberately hardcoded here. It must NOT be driven
/// by simulation state: FR-012b forbids presentation concepts from crossing the layer boundary, and
/// the tick count the renderer receives must never affect what is visible.
fragment float4 swiftsky_quad_fragment(swiftsky::RasterizerData in [[stage_in]])
{
    return float4(0.0, 0.0, 0.0, 1.0);
}
