// Water Ripple — a Ghostty custom shader: shallow water with pebble ripples at the cursor.
//
// Models the terminal as sitting behind a water surface described by a height
// field. The height field's gradient refracts the sampled terminal texture and
// produces a directional sheen, so the surface reads as moving water rather than
// a flat texture warp. Two independent sources are summed into the height field
// so they interfere by superposition:
//
//   1) Ambient undulation — a few slow, low-frequency traveling waves driven by
//      iTime. Always present, so calm regions still feel like shallow water.
//   2) Pebble wave train — a damped radial wave sin(k·r − ω·age) emitted from
//      the cursor on each cursor change. Rings expand outward across the screen,
//      shrink as they spread (energy over a growing circumference), and decay
//      toward calm. One sin term yields many concentric rings; distinct early,
//      calmer as they spread.
//
// THE STATELESS PATTERN (how this works without per-frame GPU state)
//   Ghostty custom shaders are stateless (ShaderToy format): nothing carries
//   over between frames. Dynamic/"stateful" effects are built from the built-in
//   uniforms plus time-based math on iTime, with iTimeCursorChange as an event
//   gate. Concretely this shader uses:
//     • iTime            — wall clock, drives the ambient waves.
//     • iTimeCursorChange— timestamp of the last cursor change (per keystroke;
//                          NOT retriggered by cursor blink). age = iTime − this.
//     • iCurrentCursor / iPreviousCursor — pebble origin + typing-vs-teleport
//                          classification (1 cell = typing, big jump = click).
//   Everything else is pure math recomputed per frame — no history needed.
//
//   "Faster typing → more ripples": each keystroke resets age→0, restarting a
//   fresh strong wave train near the cursor. Type fast and the vivid early rings
//   are constantly present; type slowly and occasional trains come and go; stop
//   and only the ambient water remains.
//
//   Limitation: only the SINGLE most recent keystroke is timestamped, so at most
//   one pebble train is active at a time. Multiple *simultaneously tracked*
//   pebbles from different past keystrokes are impossible without a feedback
//   buffer. The wave train's many rings + ambient interference provide the
//   "interacting ripples" feel within that constraint.
//
// All values below are tunable — see TUNING.

// ============================ TUNING =======================================
// --- Pebble (cursor drop) ---
const float RIPPLE_LIFE       = 1.8;    // seconds before the pebble fully calms
const float PEBBLE_AMP        = 1.6;    // pebble height amplitude (vs ambient)
const float WAVENUMBER        = 33.0;   // spatial k: ring spacing (higher = more/tighter rings)
const float OMEGA             = 22.0;   // temporal ω: ring propagation speed (ω/k = front speed)
const float FRONT_SPEED       = 0.67;   // UV/s the disturbance front expands at (≈ OMEGA/WAVENUMBER)
const float FRONT_WIDTH       = 0.09;   // softness of the expanding front edge
const float FALLOFF_SCALE     = 1.6;    // spatial falloff: higher = rings shrink faster outward
const float DECAY_RATE        = 0.5;    // temporal decay: higher = pebble calms sooner

// --- Ambient shallow water (always on) ---
const float AMBIENT_STRENGTH  = 0.30;   // overall ambient height amplitude
const float AMBIENT_TIME      = 0.24;   // ambient wave time scale (lower = slower/calmer)

// --- Surface rendering ---
const float REFRACTION        = 0.10;   // texture displacement from height gradient (legibility!)
const vec3  WATER_TINT        = vec3(0.62, 0.84, 1.04);  // cool water tint
const float BASELINE_TINT     = 0.04;   // constant baseline tint (always on, no flicker)
const vec3  SHEEN_COLOR       = vec3(0.20, 0.28, 0.34);  // directional sheen color
const float SHEEN_GAIN        = 0.18;   // sheen strength
const float VIGNETTE          = 1.0;    // top/bottom edge darkening (0 = none)
// ===========================================================================

const float PI = 3.1415926535897932;

// Ambient gentle shallow-water undulation: a few slow, low-frequency waves.
// Always present so calm areas still feel like water. Returns ~[-1, 1].
float ambientHeight(vec2 uv, float t) {
    float h = 0.0;
    h += sin(uv.x * 3.1 + uv.y * 2.3 + t * 0.30);
    h += sin(uv.x * 2.7 - uv.y * 3.7 + t * 0.23 + 1.7);
    h += sin((uv.x + uv.y) * 4.1 - t * 0.19 + 0.9);
    return h * (1.0 / 3.0);
}

// Pebble: a damped radial wave train expanding from `center`, gated by the most
// recent cursor change. Concentric rings grow outward and fade — distinct early,
// calmer as they spread. See header for the physics.
float pebbleHeight(vec2 uv, vec2 center, float aspect, float age, float stepGain) {
    vec2 d = vec2((uv.x - center.x) * aspect, uv.y - center.y);
    float r = length(d);

    // Outward-traveling wave train: rings move outward as `age` grows.
    float wave = sin(r * WAVENUMBER - age * OMEGA);

    // Spatial falloff: amplitude shrinks as the disturbance spreads (energy
    // distributed over a growing circumference). Smaller as it spreads outward.
    float falloff = 1.0 / (1.0 + r * FALLOFF_SCALE);

    // Temporal decay + life envelope: whole disturbance fades toward calm,
    // reaching exactly 0 at RIPPLE_LIFE (no hard pop on expiry).
    float decay    = exp(-age * DECAY_RATE);
    float lifeT    = age / RIPPLE_LIFE;
    float lifeFade = pow(max(1.0 - lifeT, 0.0), 0.8);

    // Soft causal front: disturbance exists only where it has had time to arrive
    // (r ≲ FRONT_SPEED*age), so rings EXPAND across the screen over time rather
    // than appearing everywhere instantly.
    float front  = FRONT_SPEED * age;
    float causal = 1.0 - smoothstep(front - FRONT_WIDTH, front + FRONT_WIDTH, r);

    return wave * falloff * decay * lifeFade * causal * stepGain;
}

// Total surface height = ambient + pebble. Summed here so the two interact
// (interference) before the gradient is taken.
float heightField(vec2 uv, vec2 center, float aspect, float age, float stepGain, float t) {
    return AMBIENT_STRENGTH * ambientHeight(uv, t)
         + PEBBLE_AMP * pebbleHeight(uv, center, aspect, age, stepGain);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv  = fragCoord / res;          // top-left origin (matches cursor uniforms)

    // --- Pebble origin: cursor center, in the same UV space as `uv`. ---
    // (Distance-based math is origin-invariant, so no Y flip is needed.)
    vec2 center = vec2(
        (iCurrentCursor.x + iCurrentCursor.z * 0.5) / res.x,
        (iCurrentCursor.y - iCurrentCursor.w * 0.5) / res.y
    );

    float t   = iTime;
    float age = max(iTime - iTimeCursorChange, 0.0);   // seconds since last cursor change
    float aspect = res.x / res.y;

    // Typing-vs-teleport: genuine ~1-cell keystrokes read fuller; big jumps
    // (clicks/scroll) are damped so they don't splash loudly.
    float cell   = max(iCurrentCursor.z, 1.0);
    float cells  = distance(iCurrentCursor.xy, iPreviousCursor.xy) / cell;
    float isTypingStep = smoothstep(0.5, 1.5, cells) * (1.0 - smoothstep(1.5, 6.0, cells));
    float stepGain = mix(0.35, 1.0, isTypingStep);

    // --- Height field + local surface tilt (raw per-pixel height deltas) ---
    // Using the unscaled differences keeps refraction and sheen on the same tame
    // scale; rescaling by 1/pixelSize here would blow the sheen out ~2000×.
    vec2 eps = 1.0 / res;
    float h  = heightField(uv, center, aspect, age, stepGain, t);
    float hx = heightField(uv + vec2(eps.x, 0.0), center, aspect, age, stepGain, t);
    float hy = heightField(uv + vec2(0.0, eps.y), center, aspect, age, stepGain, t);
    vec2 tilt = vec2(h - hx, h - hy);

    // --- Refraction: displace texture lookup along the surface tilt ---
    vec2 refractedUV = clamp(uv + tilt * REFRACTION, vec2(0.0), vec2(1.0));
    vec4 color = texture(iChannel0, refractedUV);

    // --- Constant baseline tint (always on, so it never flickers) ---
    color.rgb = mix(color.rgb, color.rgb * WATER_TINT, BASELINE_TINT);

    // --- Directional sheen: brighten where the surface tilts toward the light ---
    // `tilt` is small (a fraction of the wave amplitude), so this stays a faint
    // crest glint rather than a hard ring. Bump SHEEN_GAIN if you want it stronger.
    vec2 lightDir = normalize(vec2(0.4, 0.7));
    float slopeMag = length(tilt);
    float align    = clamp(dot(normalize(tilt + 1e-4), lightDir), 0.0, 1.0);
    color.rgb += SHEEN_COLOR * align * slopeMag * SHEEN_GAIN;

    // --- Vignette: gently darken the far top/bottom edges ---
    if (VIGNETTE > 0.0) {
        float vig = smoothstep(0.0, 0.30, uv.y) * smoothstep(1.0, 0.70, uv.y);
        color.rgb *= mix(1.0, mix(0.90, 1.03, vig), VIGNETTE);
    }

    fragColor = vec4(color.rgb, color.a);
}
