// swiftSky shaders.
//
// Three draws per frame, in one pass and in this order (007 FR-009): the black background, the ship,
// then any text.
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
