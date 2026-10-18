// Exercises the SIMD and BMI lifting with AVX2/BMI2 intrinsics over pseudo-random inputs, NaNs and
// out-of-range values. Built for the guest and for the host (run under Rosetta), the two checksums
// must match. MAIN_WRAPPER builds the host variant.
#include <immintrin.h>

typedef unsigned long long u64;
typedef unsigned u32;

int puts(const char*);
void exit(int);

// GROUPS selects the parts that run, to narrow down a mismatch.
#ifndef GROUPS
#define GROUPS 0x3f
#endif

static u64 hash = 0xcbf29ce484222325ull;
static u64 seed = 0x9e3779b97f4a7c15ull;

static void mix(u64 value) {
    hash ^= value;
    hash *= 0x100000001b3ull;
    hash ^= hash >> 29;
}

static u64 next(void) {
    seed ^= seed << 13;
    seed ^= seed >> 7;
    seed ^= seed << 17;
    return seed;
}

__attribute__((noinline)) static void mix128(__m128i v) {
    mix((u64)_mm_extract_epi64(v, 0));
    mix((u64)_mm_extract_epi64(v, 1));
}

__attribute__((noinline)) static void mix256(__m256i v) {
    mix128(_mm256_castsi256_si128(v));
    mix128(_mm256_extracti128_si256(v, 1));
}

static __m256i random256(void) {
    return _mm256_set_epi64x((long long)next(), (long long)next(), (long long)next(), (long long)next());
}

__attribute__((noinline)) static void integer_lanes(__m256i a, __m256i b) {
    mix256(_mm256_add_epi8(a, b)); mix256(_mm256_add_epi16(a, b)); mix256(_mm256_add_epi32(a, b)); mix256(_mm256_add_epi64(a, b));
    mix256(_mm256_sub_epi8(a, b)); mix256(_mm256_sub_epi32(a, b)); mix256(_mm256_adds_epi16(a, b)); mix256(_mm256_subs_epu8(a, b));
    mix256(_mm256_mullo_epi32(a, b)); mix256(_mm256_mullo_epi16(a, b)); mix256(_mm256_mulhi_epi16(a, b)); mix256(_mm256_mulhi_epu16(a, b));
    mix256(_mm256_mul_epi32(a, b)); mix256(_mm256_mul_epu32(a, b)); mix256(_mm256_madd_epi16(a, b));
    mix256(_mm256_min_epi32(a, b)); mix256(_mm256_max_epi32(a, b)); mix256(_mm256_min_epu8(a, b)); mix256(_mm256_max_epu16(a, b));
    mix256(_mm256_avg_epu8(a, b)); mix256(_mm256_abs_epi32(a));
    mix256(_mm256_cmpeq_epi8(a, _mm256_or_si256(a, _mm256_set1_epi8(1)))); mix256(_mm256_cmpeq_epi32(a, a));
    mix256(_mm256_cmpgt_epi32(a, b)); mix256(_mm256_cmpgt_epi64(a, b));
    mix256(_mm256_hadd_epi32(a, b)); mix256(_mm256_hsub_epi16(a, b));
    mix256(_mm256_packs_epi32(a, b)); mix256(_mm256_packs_epi16(a, b)); mix256(_mm256_packus_epi32(a, b)); mix256(_mm256_packus_epi16(a, b));
    mix128(_mm_packs_epi32(_mm256_castsi256_si128(a), _mm256_castsi256_si128(b)));
}

__attribute__((noinline)) static void shuffles(__m256i a, __m256i b) {
    mix256(_mm256_unpacklo_epi8(a, b)); mix256(_mm256_unpackhi_epi16(a, b)); mix256(_mm256_unpacklo_epi32(a, b)); mix256(_mm256_unpackhi_epi64(a, b));
    mix256(_mm256_shuffle_epi32(a, 0x1b)); mix256(_mm256_shufflelo_epi16(a, 0x6c)); mix256(_mm256_shufflehi_epi16(a, 0xb1));
    mix256(_mm256_shuffle_epi8(a, b)); mix256(_mm256_alignr_epi8(a, b, 5)); mix256(_mm256_alignr_epi8(a, b, 20));
    mix256(_mm256_slli_si256(a, 3)); mix256(_mm256_srli_si256(a, 11));
    mix256(_mm256_blend_epi16(a, b, 0xa5)); mix256(_mm256_blend_epi32(a, b, 0x3c)); mix256(_mm256_blendv_epi8(a, b, _mm256_xor_si256(a, b)));
    mix256(_mm256_permute4x64_epi64(a, 0x4e)); mix256(_mm256_permute2x128_si256(a, b, 0x21)); mix256(_mm256_permute2x128_si256(a, b, 0x83));
    mix256(_mm256_permutevar8x32_epi32(a, b));
    mix256(_mm256_inserti128_si256(a, _mm256_castsi256_si128(b), 1)); mix128(_mm256_extracti128_si256(b, 1));
    __m128i x = _mm256_castsi256_si128(a);
    mix((u64)_mm_extract_epi8(x, 13)); mix((u64)_mm_extract_epi16(x, 5)); mix((u64)_mm_extract_epi32(x, 3));
    mix128(_mm_insert_epi8(x, (int)next(), 9)); mix128(_mm_insert_epi32(x, (int)next(), 2)); mix128(_mm_insert_epi64(x, (long long)next(), 1));
    mix256(_mm256_broadcastb_epi8(x)); mix256(_mm256_broadcastw_epi16(x)); mix256(_mm256_broadcastd_epi32(x)); mix256(_mm256_broadcastq_epi64(x));
    mix256(_mm256_cvtepu8_epi32(x)); mix256(_mm256_cvtepi8_epi32(x)); mix256(_mm256_cvtepu32_epi64(x)); mix256(_mm256_cvtepi16_epi32(x));
    mix((u64)(u32)_mm256_movemask_epi8(a)); mix((u64)(u32)_mm256_movemask_ps(_mm256_castsi256_ps(b)));
    mix((u64)_mm256_testz_si256(a, b)); mix((u64)_mm256_testc_si256(a, b)); mix((u64)_mm_testz_ps(_mm_castsi128_ps(x), _mm_castsi128_ps(x)));
}

__attribute__((noinline)) static void shifts(__m256i a, __m256i b) {
    mix256(_mm256_slli_epi32(a, 7)); mix256(_mm256_srli_epi32(a, 31)); mix256(_mm256_srai_epi32(a, 9)); mix256(_mm256_srli_epi16(a, 3));
    mix256(_mm256_slli_epi64(a, 33)); mix256(_mm256_srli_epi64(a, 1));
    __m128i count = _mm_cvtsi32_si128((int)(next() & 63));
    mix256(_mm256_sll_epi32(a, count)); mix256(_mm256_sra_epi32(a, count)); mix256(_mm256_srl_epi64(a, count));
    __m256i counts = _mm256_and_si256(b, _mm256_set1_epi32(63));
    mix256(_mm256_srlv_epi32(a, counts)); mix256(_mm256_sllv_epi32(a, counts)); mix256(_mm256_srav_epi32(a, counts));
}

__attribute__((noinline)) static void masked(__m256i a, __m256i b) {
    int memory[8];
    for (int i = 0; i < 8; ++i) memory[i] = (int)next();
    __m128i mask = _mm256_castsi256_si128(b);
    mix128(_mm_maskload_epi32(memory, mask));
    _mm_maskstore_epi32(memory, mask, _mm256_castsi256_si128(a));
    _mm256_maskstore_epi32(memory, a, b);
    for (int i = 0; i < 8; ++i) mix((u64)(u32)memory[i]);
}

static const double specials[] = {0.0, -0.0, 1.5, -2.5, 3.0e9, -3.0e9, 1.0e20, 1.0 / 0.0, -1.0 / 0.0, 0.0 / 0.0, 2147483647.5, -2147483648.75};

// x86 makes new NaNs negative and arm64 positive; the translator does not model that, so NaNs are
// hashed without their sign.
__attribute__((noinline)) static void mixd(double value) {
    u64 bits;
    __builtin_memcpy(&bits, &value, 8);
    mix(value != value ? bits & ~(1ull << 63) : bits);
}

__attribute__((noinline)) static void mixf(float value) {
    u32 bits;
    __builtin_memcpy(&bits, &value, 4);
    mix(value != value ? bits & ~(1u << 31) : bits);
}

__attribute__((noinline)) static void mixpd(__m256d v) {
    double lanes[4];
    _mm256_storeu_pd(lanes, v);
    for (int i = 0; i < 4; ++i) mixd(lanes[i]);
}

__attribute__((noinline)) static void mixps(__m256 v) {
    float lanes[8];
    _mm256_storeu_ps(lanes, v);
    for (int i = 0; i < 8; ++i) mixf(lanes[i]);
}

__attribute__((noinline)) static void floats(double x, double y) {
    __m128d a = _mm_set_sd(x), b = _mm_set_sd(y);
    mixd(_mm_cvtsd_f64(_mm_add_sd(a, b))); mixd(_mm_cvtsd_f64(_mm_mul_sd(a, b))); mixd(_mm_cvtsd_f64(_mm_div_sd(a, b)));
    mixd(_mm_cvtsd_f64(_mm_sub_sd(a, b))); mixd(_mm_cvtsd_f64(_mm_min_sd(a, b))); mixd(_mm_cvtsd_f64(_mm_max_sd(a, b)));
    mixd(_mm_cvtsd_f64(_mm_sqrt_sd(a, b))); mixd(_mm_cvtsd_f64(_mm_round_sd(a, b, _MM_FROUND_TO_NEG_INF)));
    mix((u64)_mm_comilt_sd(a, b)); mix((u64)_mm_ucomieq_sd(a, b)); mix((u64)_mm_ucomineq_sd(a, b)); mix((u64)_mm_comige_sd(a, b));
    mix((u64)_mm_cvttsd_si32(a)); mix((u64)_mm_cvttsd_si64(a)); mix((u64)_mm_cvtsd_si32(a));
    __m128 fa = _mm_set_ss((float)x), fb = _mm_set_ss((float)y);
    mixf(_mm_cvtss_f32(_mm_add_ss(fa, fb))); mixf(_mm_cvtss_f32(_mm_div_ss(fa, fb))); mixf(_mm_cvtss_f32(_mm_max_ss(fa, fb)));
    mix((u64)(u32)_mm_cvtsi128_si32(_mm_castps_si128(_mm_cmplt_ss(fa, fb))));
    mix((u64)(u32)_mm_cvtsi128_si32(_mm_castps_si128(_mm_cmpunord_ss(fa, fb))));
    mix((u64)_mm_cvttss_si32(fa)); mix((u64)_mm_ucomilt_ss(fa, fb));
    mixd(_mm_cvtsd_f64(_mm_cvtss_sd(a, fa))); mixf(_mm_cvtss_f32(_mm_cvtsd_ss(fa, b)));
    mixd(_mm_cvtsd_f64(_mm_cvtsi64_sd(a, (long long)next()))); mixf(_mm_cvtss_f32(_mm_cvtsi32_ss(fa, (int)next())));
    __m256d pd = _mm256_set_pd(x, y, x * 3, y - 1);
    __m256 ps = _mm256_set_ps((float)x, (float)y, 1.0f, -1.0f, (float)(x + y), 0.5f, (float)(x * y), 2.0f);
    mixpd(_mm256_mul_pd(pd, pd)); mixpd(_mm256_add_pd(pd, pd));
    mixps(_mm256_mul_ps(ps, ps)); mixps(_mm256_permute_ps(ps, 0x93));
    mixpd(_mm256_permute_pd(pd, 0x5)); mixps(_mm256_shuffle_ps(ps, ps, 0x2d));
    mixps(_mm256_permutevar_ps(ps, random256()));
    mixps(_mm256_movehdup_ps(ps)); mixps(_mm256_blendv_ps(ps, _mm256_set1_ps(7.0f), _mm256_castsi256_ps(random256())));
    mixps(_mm256_zextps128_ps256(_mm256_cvtpd_ps(pd))); mix256(_mm256_cvttps_epi32(ps)); mixps(_mm256_cvtepi32_ps(random256()));
    mixpd(_mm256_cvtepi32_pd(_mm256_castsi256_si128(random256()))); mix128(_mm256_cvttpd_epi32(pd));
    mixps(_mm256_broadcastss_ps(fa)); mixpd(_mm256_broadcastsd_pd(b));
    mixps(_mm256_zextps128_ps256(_mm_insert_ps(fa, fb, 0x5a))); mixps(_mm256_zextps128_ps256(_mm_movelh_ps(fa, fb)));
    mixd(_mm_cvtsd_f64(_mm_fmadd_sd(a, b, a))); mixd(_mm_cvtsd_f64(_mm_fnmadd_sd(a, b, b))); mixf(_mm_cvtss_f32(_mm_fmsub_ss(fa, fb, fa)));
    mixps(_mm256_fmadd_ps(ps, ps, ps)); mixpd(_mm256_fnmsub_pd(pd, pd, pd));
    mixpd(_mm256_zextpd128_pd256(_mm_unpacklo_pd(a, b))); mix256(_mm256_castps_si256(_mm256_cmp_ps(ps, _mm256_set1_ps(1.0f), _CMP_GE_OQ)));
}

__attribute__((noinline)) static void bits(u64 a, u64 b) {
    mix(_andn_u64(a, b)); mix(_bextr_u64(a, (u32)(b & 0x3f), (u32)((b >> 8) & 0x7f))); mix(_bzhi_u64(a, (u32)(b & 0x7f)));
    mix(a << (b & 63)); mix(a >> (b & 63)); mix((u64)((long long)a >> (b & 63)));
    mix(_blsi_u64(a)); mix(_blsr_u64(a)); mix(_blsmsk_u64(a)); mix(_pdep_u64(a, b)); mix(_pext_u64(a, b));
    unsigned long long high;
    mix(_mulx_u64(a, b, &high)); mix(high);
    mix((u64)__builtin_bswap64(a)); mix((a >> 13) | (a << 51));
    mix((u64)_lzcnt_u64(a >> (b & 63))); mix((u64)_tzcnt_u64(a << (b & 63))); mix((u64)__builtin_popcountll(a));
}

void _start(void* block) {
    (void)block;
    for (int round = 0; round < 64; ++round) {
        __m256i a = random256(), b = random256();
        if (GROUPS & 1) integer_lanes(a, b);
        if (GROUPS & 2) shuffles(a, b);
        if (GROUPS & 4) shifts(a, b);
        if (GROUPS & 8) masked(a, b);
        u64 x = next(), y = next();
        if (GROUPS & 16) bits(x, y);
    }
    for (unsigned i = 0; i < sizeof(specials) / sizeof(specials[0]); ++i) {
        for (unsigned j = 0; j < sizeof(specials) / sizeof(specials[0]); ++j) {
            if (GROUPS & 32) floats(specials[i], specials[j]);
        }
    }
    for (int round = 0; round < 64; ++round) {
        double x = (double)(long long)next() / 1e9, y = (double)(long long)next() / 1e12;
        if (GROUPS & 32) floats(x, y);
    }
    char text[17];
    for (int i = 0; i < 16; ++i) text[i] = "0123456789abcdef"[(hash >> (60 - 4 * i)) & 15];
    text[16] = 0;
    puts(text);
    exit((int)(hash & 0x7f));
}

#ifdef MAIN_WRAPPER
int main(void) {
    _start(0);
    return 0;
}
#endif
