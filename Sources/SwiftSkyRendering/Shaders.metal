// swiftSky shaders.
//
// Draws per frame, in one pass and in this order (007 FR-009, 014 FR-009): the black background, the
// order overlay while an order is flown, the ship, then any text.
//
// The background is a full-screen quad rendered as a triangle strip, filled black. It is trivial by
// design: the point of 001 FR-002a is that a real draw path exists and is exercised. A pass that merely
// cleared the surface would leave shader compilation, pipeline-state creation, geometry binding and
// draw submission untested. Its vertex positions arrive in clip space, so a surface resize changes the
// viewport and nothing else. There is no resize-time geometry update to get wrong (research.md R11).

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

// MARK: - Text (002-metal-text-rendering)
//
// One instanced draw per frame: each instance is one character, expanded here into a quad the size of
// one atlas cell. Positions arrive already snapped to whole surface pixels and the atlas is sampled
// with nearest filtering, so each atlas texel lands on exactly one surface pixel — nothing is
// resampled, which is what keeps text as sharp as the system's own (FR-009, research.md R3).

namespace swiftsky {

/// One character. Mirrors `GlyphInstance` on the Swift side byte for byte — 8 bytes.
struct GlyphInstance {
    ushort x;
    ushort y;
    ushort cell;
    ushort padding;
};

/// Per-draw constants, passed with `setVertexBytes`. Mirrors `TextRenderer.Uniforms`.
struct TextUniforms {
    float2 viewportPixels;
    float2 cellPixels;
    uint atlasColumns;
    uint padding;
};

struct TextRasterizerData {
    float4 position [[position]];
    float2 texel;
};

}  // namespace swiftsky

vertex swiftsky::TextRasterizerData swiftsky_text_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device swiftsky::GlyphInstance *instances [[buffer(0)]],
    constant swiftsky::TextUniforms &uniforms [[buffer(1)]])
{
    const swiftsky::GlyphInstance glyph = instances[instanceID];

    // Triangle-strip corners: (0,0) (1,0) (0,1) (1,1), in cell units, y down.
    const float2 corner = float2(vertexID & 1, vertexID >> 1);

    const float2 pixel = float2(glyph.x, glyph.y) + corner * uniforms.cellPixels;
    const float2 cellOrigin = float2(glyph.cell % uniforms.atlasColumns, glyph.cell / uniforms.atlasColumns)
                              * uniforms.cellPixels;

    swiftsky::TextRasterizerData out;
    // Surface pixels (y down) to clip space (y up).
    out.position = float4(pixel.x / uniforms.viewportPixels.x * 2.0 - 1.0,
                          1.0 - pixel.y / uniforms.viewportPixels.y * 2.0,
                          0.0, 1.0);
    out.texel = cellOrigin + corner * uniforms.cellPixels;
    return out;
}

/// White text, premultiplied. The atlas holds coverage written as Core Graphics blends — in encoded
/// space — while this sRGB surface blends in linear space. Decoding the coverage first makes text over
/// black match the system's rendering exactly; used as-is, anti-aliased edges come out brighter and
/// the text looks bold (research.md R4, SC-001).
fragment float4 swiftsky_text_fragment(
    swiftsky::TextRasterizerData in [[stage_in]],
    texture2d<float> atlas [[texture(0)]])
{
    constexpr sampler nearest(coord::pixel, filter::nearest, address::clamp_to_zero);
    const float coverage = atlas.sample(nearest, in.texel).r;
    const float a = coverage <= 0.04045 ? coverage / 12.92 : pow((coverage + 0.055) / 1.055, 2.4);
    return float4(a, a, a, a);
}

// MARK: - Ship sprite (007-ship-sprite-rendering)
//
// One textured quad: the ship image, blended over the black background. The four corners arrive
// already placed, in clip space, from `ShipSpritePlacement`. This shader does no placement maths of its
// own, so the tested corners are the drawn corners (007 research R5).
//
// Colour (research R3): the texture is premultiplied, sRGB-encoded RGBA8 in an `rgba8Unorm_srgb`
// texture, so sampling decodes the colour to linear and leaves alpha alone. Blended `one` /
// `oneMinusSourceAlpha` into the sRGB surface, a pixel over black stores exactly the encoded α·c that
// Core Graphics gives when it draws the image over black.
//
// Filtering (research R4): trilinear over a mip chain built once at start-up. At 2× and quarter turns,
// surface pixel centres fall on texel centres, so each texel lands on exactly one pixel. At 1× the
// 40 × 40 level is read, so a turning ship does not shimmer. Outside the image the sample is
// transparent, so the quad's edge never shows.

namespace swiftsky {

struct SpriteRasterizerData {
    float4 position [[position]];
    float2 uv;
};

}  // namespace swiftsky

/// Corners in triangle-strip order: bottom-left, bottom-right, top-left, top-right. That matches
/// `ShipSpritePlacement.clipCorners`. The image's top row is v = 0.
vertex swiftsky::SpriteRasterizerData swiftsky_sprite_vertex(
    uint vertexID [[vertex_id]],
    constant float2 *corners [[buffer(0)]])
{
    swiftsky::SpriteRasterizerData out;
    out.position = float4(corners[vertexID], 0.0, 1.0);
    out.uv = float2(vertexID & 1, 1 - (vertexID >> 1));
    return out;
}

/// The premultiplied sample, as is. The blend state does the rest.
fragment float4 swiftsky_sprite_fragment(
    swiftsky::SpriteRasterizerData in [[stage_in]],
    texture2d<float> image [[texture(0)]])
{
    constexpr sampler trilinear(filter::linear, mip_filter::linear, address::clamp_to_zero);
    return image.sample(trilinear, in.uv);
}

// MARK: - Order overlay (014-order-overlay)
//
// Two instanced draws while an order is flown: the planned path's line, one quad per segment, then two
// rings (the destination marker and the ship highlight), one quad each. One fragment shader covers
// both from a distance field (research R4): the distance d from the pixel centre to the segment
// p0 → p1, and coverage halfWidth + 0.5 − |d − radius|, clamped to 0…1 — a one-pixel anti-aliased edge.
// A line segment has radius 0, which makes it a capsule with round ends; a ring has p0 = p1. Everything
// arrives in surface pixels from `OrderOverlay`, +y down, which is also what `[[position]]` gives the
// fragment shader, so the shape is drawn where the tests put it.
//
// Blending is `max`, not "over" (research R5): consecutive capsules overlap at every joint, and "over"
// would brighten each overlap. The overlay is drawn on the black background only, where `max` and
// "over" agree.

namespace swiftsky {

/// Mirrors `OrderOverlayUniforms` on the Swift side — 32 bytes.
struct OverlayUniforms {
    float2 surfacePixels;
    float lineHalfWidth;
    float unused;
    float4 colour;  // linear, premultiplied
};

/// Mirrors `OrderOverlayRing` on the Swift side — 16 bytes.
struct OverlayRing {
    float2 centre;
    float radius;
    float halfWidth;
};

struct OverlayRasterizerData {
    float4 position [[position]];
    float2 p0 [[flat]];
    float2 p1 [[flat]];
    float radius [[flat]];
    float halfWidth [[flat]];
};

/// Surface pixels (+y down) → clip space (edges at ±1, +y up).
inline float4 overlayClip(float2 pixel, float2 surface) {
    return float4(pixel.x / surface.x * 2.0 - 1.0, 1.0 - pixel.y / surface.y * 2.0, 0.0, 1.0);
}

}  // namespace swiftsky

/// Instance i is the segment points[i] → points[i + 1], as a quad grown by the half width plus one
/// pixel on every side. Vertex order for the strip: start −n, start +n, end −n, end +n.
vertex swiftsky::OverlayRasterizerData swiftsky_overlay_line_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant float2 *points [[buffer(0)]],
    constant swiftsky::OverlayUniforms &uniforms [[buffer(1)]])
{
    const float2 a = points[instanceID];
    const float2 b = points[instanceID + 1];
    const float2 delta = b - a;
    const float len = length(delta);
    const float2 along = len > 0.0 ? delta / len : float2(1.0, 0.0);
    const float2 across = float2(-along.y, along.x);
    const float reach = uniforms.lineHalfWidth + 1.0;

    const float2 end = (vertexID & 2) ? b + along * reach : a - along * reach;
    const float2 corner = end + across * ((vertexID & 1) ? reach : -reach);

    swiftsky::OverlayRasterizerData out;
    out.position = swiftsky::overlayClip(corner, uniforms.surfacePixels);
    out.p0 = a;
    out.p1 = b;
    out.radius = 0.0;
    out.halfWidth = uniforms.lineHalfWidth;
    return out;
}

/// Instance i is rings[i], as a square of half side radius + half width + one pixel.
vertex swiftsky::OverlayRasterizerData swiftsky_overlay_ring_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant swiftsky::OverlayRing *rings [[buffer(0)]],
    constant swiftsky::OverlayUniforms &uniforms [[buffer(1)]])
{
    const swiftsky::OverlayRing ring = rings[instanceID];
    const float reach = ring.radius + ring.halfWidth + 1.0;
    const float2 corner = ring.centre + float2((vertexID & 1) ? reach : -reach, (vertexID & 2) ? reach : -reach);

    swiftsky::OverlayRasterizerData out;
    out.position = swiftsky::overlayClip(corner, uniforms.surfacePixels);
    out.p0 = ring.centre;
    out.p1 = ring.centre;
    out.radius = ring.radius;
    out.halfWidth = ring.halfWidth;
    return out;
}

/// The style colour times the shape's coverage of this pixel, premultiplied.
fragment float4 swiftsky_overlay_fragment(
    swiftsky::OverlayRasterizerData in [[stage_in]],
    constant swiftsky::OverlayUniforms &uniforms [[buffer(0)]])
{
    const float2 p = in.position.xy;
    const float2 segment = in.p1 - in.p0;
    const float lengthSquared = dot(segment, segment);
    const float t = lengthSquared > 0.0 ? clamp(dot(p - in.p0, segment) / lengthSquared, 0.0, 1.0) : 0.0;
    const float d = distance(p, in.p0 + segment * t);
    const float coverage = clamp(in.halfWidth + 0.5 - abs(d - in.radius), 0.0, 1.0);
    return uniforms.colour * coverage;
}
