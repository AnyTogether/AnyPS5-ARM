// Shared by the frame generation passes: three sampled inputs, one storage output and the same
// push constants, so one pipeline layout serves them all.
layout(local_size_x = 8, local_size_y = 8) in;

layout(set = 0, binding = 0) uniform sampler2D inputA;
layout(set = 0, binding = 1) uniform sampler2D inputB;
layout(set = 0, binding = 2) uniform sampler2D inputC;

layout(push_constant) uniform Push {
    ivec4 a;
    ivec4 b;
    vec4 c;
} push;

float luma(vec3 color) {
    return dot(color, vec3(0.299, 0.587, 0.114));
}
