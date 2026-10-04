// The base materials a scene's layers and particles draw with, which ship
// with Wallpaper Engine and not with its items. These are ours,
// written from scratch; each pair says so in its first lines.
// Constants for the same reason as `ShaderHeaders`.

/// A program's two stages of GLSL, and where they came from.
struct ShaderSources: Sendable {
    var vertex: String
    var fragment: String
    /// "item", the scene's own source, or "builtin", ours (`ScenePrograms.Entry.origin`).
    var origin: String
}

/// Our base materials: an image layer's (`genericimage`, which also serves
/// `genericimage2` and `genericimage4`) and a particle's (`genericparticle`).
enum BaseMaterials {
    /// Ours for a shader the scene does not carry, or nil when we have none.
    static func sources(for shader: String) -> ShaderSources? {
        if shader.hasPrefix("genericimage") {
            return ShaderSources(vertex: imageVertex, fragment: imageFragment, origin: "builtin")
        }
        if shader == "genericparticle" {
            return ShaderSources(vertex: particleVertex, fragment: particleFragment, origin: "builtin")
        }
        return nil
    }

    static let imageVertex = #"""
        // Livepaper S9. Written from scratch: Wallpaper Engine's base image shaders (genericimage, genericimage2,
        // genericimage4) ship with Wallpaper Engine, not with the items, so all three names resolve to this pair.
        // An image layer draws its texture, or the current frame of a sprite sheet, tinted. With SKINNING, a
        // puppet's mesh is posed by up to 32 bones (the engine folds the pixel-to-quad scale into the matrices).

        uniform mat4 g_ModelViewProjectionMatrix;
        // Where the image (or the sprite frame) sits inside the texture: xy origin, zw size, in UV units.
        uniform vec4 g_FrameRect;

        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;

        #if SKINNING
        attribute vec4 a_BlendIndices;
        attribute vec4 a_BlendWeights;
        uniform mat4 g_Bones[32];
        #endif

        varying vec2 v_TexCoord;

        void main() {
        #if SKINNING
        	vec4 p = vec4(a_Position, 1.0);
        	vec4 skinned = mul(p, g_Bones[int(a_BlendIndices.x)]) * a_BlendWeights.x +
        		mul(p, g_Bones[int(a_BlendIndices.y)]) * a_BlendWeights.y +
        		mul(p, g_Bones[int(a_BlendIndices.z)]) * a_BlendWeights.z +
        		mul(p, g_Bones[int(a_BlendIndices.w)]) * a_BlendWeights.w;
        	gl_Position = mul(vec4(skinned.xyz, 1.0), g_ModelViewProjectionMatrix);
        #else
        	gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
        #endif
        	v_TexCoord = g_FrameRect.xy + a_TexCoord * g_FrameRect.zw;
        }

        """#

    static let imageFragment = #"""
        // Livepaper S9. Written from scratch (see genericimage.vert).

        uniform sampler2D g_Texture0;
        uniform vec4 g_Color4; // rgb tint times brightness, a = layer alpha

        varying vec2 v_TexCoord;

        void main() {
        	vec4 albedo = texSample2D(g_Texture0, v_TexCoord);
        	gl_FragColor = albedo * g_Color4;
        }

        """#

    static let particleVertex = #"""
        // Livepaper S9. Written from scratch: Wallpaper Engine's genericparticle ships with Wallpaper Engine, not
        // with the items. A textured, tinted sprite; the particle system on the CPU fills position, UV and colour.

        uniform mat4 g_ModelViewProjectionMatrix;

        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        attribute vec4 a_Color;

        varying vec2 v_TexCoord;
        varying vec4 v_Color;

        void main() {
        	gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
        	v_TexCoord = a_TexCoord;
        	v_Color = a_Color;
        }

        """#

    static let particleFragment = #"""
        // Livepaper S9. Written from scratch (see genericparticle.vert).

        uniform sampler2D g_Texture0;

        varying vec2 v_TexCoord;
        varying vec4 v_Color;

        void main() {
        	gl_FragColor = texSample2D(g_Texture0, v_TexCoord) * v_Color;
        }

        """#
}
