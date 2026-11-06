#version 300 es
precision highp float;



uniform vec2 uSize;
uniform sampler2D uBackgroundTexture;

out vec4 frag_color;

void main() {
  vec2 position = vec2(gl_FragCoord.x,uSize.y-gl_FragCoord.y);


  vec2 center = uSize * 0.5;
  vec2 radial = position - center;
  float radius = min(uSize.x, uSize.y) * 0.5;
  float normalizedRadius = clamp(length(radial) / radius, 0.0, 0.98);

  float capHeight = 1.4;
  float surfaceSlope = (capHeight / radius) * normalizedRadius /
      sqrt(max(1.0 - normalizedRadius * normalizedRadius, 0.04));
  float incidence = atan(surfaceSlope);
  float transmission = asin(clamp(sin(incidence) / 1.52, 0.0, 0.99));
  float shift = clamp((incidence - transmission) * 8.0, 0.0, 0.45);
  shift *= smoothstep(0.08, 0.42, normalizedRadius);

  vec2 direction = radial / max(length(radial), 0.001);
  vec2 samplePosition = position + direction * shift;
  vec2 uv = clamp(samplePosition / uSize, vec2(0.001), vec2(0.999));
  frag_color = texture(uBackgroundTexture, uv);
}
