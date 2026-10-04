// The headers a scene's shaders include, which ship with Wallpaper Engine and
// not with its items. These four are ours, written from scratch
// and inferred from how the items' own shaders use them; none of
// them is Wallpaper Engine's file. Each says so in its first lines. They are
// constants rather than package resources, so that the app and anything else
// that imports carry no resource bundle.

/// Our headers, which the translator writes into its work folder for glslang's
/// `#include` to find. `common.h` is also put in front of every stage, since a
/// shader may use it without including it.
enum ShaderHeaders {
    /// File name to text.
    static let all: [String: String] = [
        "common.h": common,
        "common_blending.h": blending,
        "common_blur.h": blur,
        "common_perspective.h": perspective,
    ]

    static let common = #"""
        // Livepaper S9. Written from scratch for the GLSL dialect the Workshop items' own shaders are written in;
        // every definition here is inferred from how those shaders use it. It is not Wallpaper Engine's file.
        // Prepended to every stage, so a shader that never includes it still gets it (Gaze's waterripple.frag).
        #ifndef LP_COMMON_H
        #define LP_COMMON_H

        #define M_PI 3.14159265358979
        #define M_PI_HALF 1.57079632679490
        // Simple_Audio_Bars computes (atan2(y, x) + M_PI) / M_PI_2 and treats it as 0..1: here it is a full turn.
        #define M_PI_2 6.28318530717959
        #define SQRT_2 1.41421356237310

        // HLSL spellings the shaders use.
        #define texSample2D texture
        #define texSample2DLod textureLod
        #define frac fract
        #define lerp mix
        #define atan2 atan
        #define ddx dFdx
        #define ddy dFdy
        #define saturate(x) clamp((x), 0.0, 1.0)
        #define fmod(x, y) ((x) - (y) * trunc((x) / (y)))
        #define log10(x) (log2(x) * 0.301029995664)
        #define CAST2(x) vec2(x)
        #define CAST3(x) vec3(x)
        #define CAST4(x) vec4(x)
        #define CAST3X3(x) mat3(x)

        // mul(v, M) is a row vector times a matrix. Our matrices are GLSL column-major, so it is M * v.
        #define mul(a, b) ((b) * (a))

        vec2 rotateVec2(vec2 v, float r) {
            float c = cos(r);
            float s = sin(r);
            return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
        }

        float greyscale(vec3 c) {
            return dot(c, vec3(0.2126, 0.7152, 0.0722));
        }

        // shift_hue.frag calls these without defining them. Hue, saturation, value in 0..1 (hexcone model).
        vec3 rgb2hsv(vec3 c) {
            float mx = max(c.r, max(c.g, c.b));
            float mn = min(c.r, min(c.g, c.b));
            float d = mx - mn;
            float h = 0.0;
            if (d > 1e-6) {
                if (mx == c.r) h = (c.g - c.b) / d;
                else if (mx == c.g) h = 2.0 + (c.b - c.r) / d;
                else h = 4.0 + (c.r - c.g) / d;
                h = fract(h / 6.0);
            }
            return vec3(h, mx > 1e-6 ? d / mx : 0.0, mx);
        }

        vec3 hsv2rgb(vec3 c) {
            vec3 k = clamp(abs(fract(c.x + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
            return c.z * mix(vec3(1.0), k, c.y);
        }

        // `sample` is a GLSL 4 keyword; several shaders use it as a variable name.
        #define sample lpSample

        // HLSL truncates a wider vector silently; GLSL does not. The one case the samples hit
        // (shift_hue.frag: albedo.rgb = mix(albedo, newAlbedo, mask)) gets an overload.
        vec3 mix(vec4 a, vec3 b, float t) { return mix(a.rgb, b, t); }

        #endif

        """#

    static let blending = #"""
        // Livepaper S9. Written from scratch. ApplyBlending(BLENDMODE, base, blend, opacity) with BLENDMODE an
        // "imageblending" combo. The numbering is a guess: Photoshop's menu order without Dissolve fits every
        // default the samples declare (blend.frag 2 = multiply, pulse and godrays_combine 9 = linear dodge,
        // filmgrain 12 = soft light). Not verified against Wallpaper Engine.
        #ifndef LP_COMMON_BLENDING_H
        #define LP_COMMON_BLENDING_H

        float lpLum(vec3 c) { return dot(c, vec3(0.3, 0.59, 0.11)); }

        vec3 lpClipColor(vec3 c) {
            float l = lpLum(c);
            float n = min(min(c.r, c.g), c.b);
            float x = max(max(c.r, c.g), c.b);
            if (n < 0.0) c = l + (c - l) * l / max(l - n, 1e-5);
            if (x > 1.0) c = l + (c - l) * (1.0 - l) / max(x - l, 1e-5);
            return c;
        }

        vec3 lpSetLum(vec3 c, float l) { return lpClipColor(c + (l - lpLum(c))); }

        float lpSat(vec3 c) { return max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b); }

        vec3 lpSetSat(vec3 c, float s) {
            float mx = max(max(c.r, c.g), c.b);
            float mn = min(min(c.r, c.g), c.b);
            return mx > mn ? (c - mn) * s / (mx - mn) : vec3(0.0);
        }

        vec3 lpOverlay(vec3 a, vec3 b) {
            return mix(2.0 * a * b, 1.0 - 2.0 * (1.0 - a) * (1.0 - b), step(0.5, a));
        }

        vec3 lpSoftLight(vec3 a, vec3 b) {
            vec3 d = mix(sqrt(a), ((16.0 * a - 12.0) * a + 4.0) * a, step(a, vec3(0.25)));
            return mix(a + (2.0 * b - 1.0) * (d - a), a - (1.0 - 2.0 * b) * a * (1.0 - a), step(b, vec3(0.5)));
        }

        vec3 lpBlend(int mode, vec3 a, vec3 b) {
            if (mode == 0) return b;                                                      // normal
            if (mode == 1) return min(a, b);                                              // darken
            if (mode == 2) return a * b;                                                  // multiply
            if (mode == 3) return 1.0 - min(vec3(1.0), (1.0 - a) / max(b, 1e-5));         // colour burn
            if (mode == 4) return max(a + b - 1.0, 0.0);                                  // linear burn
            if (mode == 5) return lpLum(b) < lpLum(a) ? b : a;                            // darker colour
            if (mode == 6) return max(a, b);                                              // lighten
            if (mode == 7) return 1.0 - (1.0 - a) * (1.0 - b);                            // screen
            if (mode == 8) return min(vec3(1.0), a / max(1.0 - b, 1e-5));                 // colour dodge
            if (mode == 9) return a + b;                                                  // linear dodge (add)
            if (mode == 10) return lpLum(b) > lpLum(a) ? b : a;                           // lighter colour
            if (mode == 11) return lpOverlay(a, b);                                       // overlay
            if (mode == 12) return lpSoftLight(a, b);                                     // soft light
            if (mode == 13) return lpOverlay(b, a);                                       // hard light
            if (mode == 14) return mix(1.0 - min(vec3(1.0), (1.0 - a) / max(2.0 * b, 1e-5)),
                                       min(vec3(1.0), a / max(2.0 * (1.0 - b), 1e-5)), step(0.5, b)); // vivid light
            if (mode == 15) return a + 2.0 * b - 1.0;                                     // linear light
            if (mode == 16) return mix(min(a, 2.0 * b), max(a, 2.0 * b - 1.0), step(0.5, b)); // pin light
            if (mode == 17) return step(1.0, a + b);                                      // hard mix
            if (mode == 18) return abs(a - b);                                            // difference
            if (mode == 19) return a + b - 2.0 * a * b;                                   // exclusion
            if (mode == 20) return a - b;                                                 // subtract
            if (mode == 21) return a / max(b, 1e-5);                                      // divide
            if (mode == 22) return lpSetLum(lpSetSat(b, lpSat(a)), lpLum(a));             // hue
            if (mode == 23) return lpSetLum(lpSetSat(a, lpSat(b)), lpLum(a));             // saturation
            if (mode == 24) return lpSetLum(b, lpLum(a));                                 // colour
            if (mode == 25) return lpSetLum(a, lpLum(b));                                 // luminosity
            return b;
        }

        vec3 ApplyBlending(int mode, vec3 a, vec3 b, float opacity) {
            return mix(a, lpBlend(mode, a, b), opacity);
        }

        #endif

        """#

    static let blur = #"""
        // Livepaper S9. Written from scratch. The shaders call blur13a / blur7a / blur3a(uv, step) with no
        // texture argument, sometimes before they declare g_Texture0, so these are macros that pick up
        // g_Texture0 where they are used. Weights are binomial (a close fit to a Gaussian).
        #ifndef LP_COMMON_BLUR_H
        #define LP_COMMON_BLUR_H

        vec4 lpBlur13(sampler2D t, vec2 uv, vec2 d) {
            const float w[7] = float[7](924.0, 792.0, 495.0, 220.0, 66.0, 12.0, 1.0);
            vec4 sum = texture(t, uv) * w[0];
            for (int i = 1; i < 7; i++) {
                sum += (texture(t, uv + d * float(i)) + texture(t, uv - d * float(i))) * w[i];
            }
            return sum / 4096.0;
        }

        vec4 lpBlur7(sampler2D t, vec2 uv, vec2 d) {
            const float w[4] = float[4](20.0, 15.0, 6.0, 1.0);
            vec4 sum = texture(t, uv) * w[0];
            for (int i = 1; i < 4; i++) {
                sum += (texture(t, uv + d * float(i)) + texture(t, uv - d * float(i))) * w[i];
            }
            return sum / 64.0;
        }

        vec4 lpBlur3(sampler2D t, vec2 uv, vec2 d) {
            return (texture(t, uv - d) + 2.0 * texture(t, uv) + texture(t, uv + d)) * 0.25;
        }

        #define blur13a(uv, d) lpBlur13(g_Texture0, uv, d)
        #define blur7a(uv, d) lpBlur7(g_Texture0, uv, d)
        #define blur3a(uv, d) lpBlur3(g_Texture0, uv, d)

        #endif

        """#

    static let perspective = #"""
        // Livepaper S9. Written from scratch. waterripple.vert and waterwaves.vert call
        // inverse(squareToQuad(p0, p1, p2, p3)) and then mul(vec3(uv, 1), xform), dividing xy by z in the
        // fragment stage: so squareToQuad is the projective map taking the unit square's corners
        // (0,0) (1,0) (1,1) (0,1) to p0 p1 p2 p3. Standard homography of a square onto a quadrilateral.
        #ifndef LP_COMMON_PERSPECTIVE_H
        #define LP_COMMON_PERSPECTIVE_H

        mat3 squareToQuad(vec2 p0, vec2 p1, vec2 p2, vec2 p3) {
            vec2 d1 = p1 - p2;
            vec2 d2 = p3 - p2;
            vec2 d3 = p0 - p1 + p2 - p3;
            float det = d1.x * d2.y - d2.x * d1.y;
            float g = (d3.x * d2.y - d2.x * d3.y) / det;
            float h = (d1.x * d3.y - d3.x * d1.y) / det;
            float a = p1.x - p0.x + g * p1.x;
            float b = p3.x - p0.x + h * p3.x;
            float d = p1.y - p0.y + g * p1.y;
            float e = p3.y - p0.y + h * p3.y;
            // Columns: (x', y', w) = M * (u, v, 1).
            return mat3(a, d, g,
                        b, e, h,
                        p0.x, p0.y, 1.0);
        }

        #endif

        """#
}
