// Game-space rectangles and strided reads from scaled Metal allocations, without game assets.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int failed;
#define CHECK(c, label) do { if (!(c)) { fprintf(stderr, "FAIL: %s\n", label); failed++; } } while (0)

static tex_t target(uint64_t serial, unsigned w, unsigned h, unsigned levels) {
    tex_t t = {.magic=MAGIC('T','E','X',0), .serial=serial};
    t.d = (nvn_texdesc){.target=NVN_TEXTURE_TARGET_2D, .format=NVN_FORMAT_RGBA8, .width=w, .height=h,
        .depth=1, .levels=levels, .samples=1, .flags=NVN_TEXTURE_FLAGS_COMPRESSIBLE};
    nvn_tex_layout(&t.d, &t.L);
    return t;
}
static void expect_pixels(const tex_t *t, id<MTLTexture> mt, unsigned lv, unsigned x, unsigned y, unsigned w, unsigned h, uint32_t colour) {
    NSUInteger tw = mt.width >> lv, th = mt.height >> lv;
    id<MTLBuffer> buf = [g_dev newBufferWithLength:tw*th*4 options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> cb = q_cb(); id<MTLBlitCommandEncoder> e = enc_b_begin(cb);
    [e copyFromTexture:mt sourceSlice:0 sourceLevel:lv sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(tw,th,1)
              toBuffer:buf destinationOffset:0 destinationBytesPerRow:tw*4 destinationBytesPerImage:tw*th*4];
    enc_b_end(e); [cb commit]; [cb waitUntilCompleted];
    CHECK(cb.status == MTLCommandBufferStatusCompleted, "raw verification blit completed");
    const uint32_t *p = buf.contents;
    CHECK(p[y*tw+x] == colour && p[(y+h-1)*tw+x+w-1] == colour, "first and last physical pixels cleared");
    CHECK(p[y*tw+x-1] != colour && p[y*tw+x+w] != colour && p[(y-1)*tw+x] != colour && p[(y+h)*tw+x] != colour,
          "pixels immediately outside physical clear untouched");
    uint32_t out[6] = {0,0,0x12345678,0,0,0x12345678};
    mtl_read_texels(t, lv, 0, &(NVNcopyRegion){97,17,0,2,2,1}, (uint8_t *)out, 12, sizeof out);
    CHECK(out[0] == colour && out[1] == colour && out[3] == colour && out[4] == colour, "strided CPU read uses scaled texels");
    CHECK(out[2] == 0x12345678 && out[5] == 0x12345678, "CPU read preserves row padding");
}

int main(int argc, char **argv) { @autoreleasepool {
    if (argc != 2 && argc != 3) return 2;
    float k = strtof(argv[1], NULL);
    uint8_t state[32] = {0}; memcpy(state + 0x10, &k, sizeof k);
    module_t main = {.name="main", .build_id="b1f12fd919eae86ab8a978317677e64b"};
    if (argc == 3 || DM_GAME_PROGRAM_ID != 0x0100f43008c44000ull) main.build_id[0] = '0';
    g_mod = &main; g_nmod = 1;
    extern uint8_t *dm_fps_state; dm_fps_state = state;
    float want = argc == 2 && DM_GAME_PROGRAM_ID == 0x0100f43008c44000ull ? k : 1.0f;
    mtl_init(); mtl_sub_begin();
    tex_t t = target(76501,192,108,1), shadow = target(76502,1024,1024,1);
    mtl_tex_init(&t); mtl_tex_init(&shadow);
    id<MTLTexture> mt = tex_mtl(&t);
    CHECK(mt.width == 192 * want && mt.height == 108 * want, "physical scene attachment");
    CHECK(tex_mtl(&shadow).width == 1024 && rs_of(tex_mtl(&shadow)) == 1, "square/shadow attachment stays native");
    if (failed) return 1;

    p_clear_tex whole = {.tex=&t, .r={0,0,0,192,108,1}, .mask=15, .c.f={1,1,1,1}};
    clear_tex(&whole);
    R.has_rt = R.has_sc = 1; R.rt.n = 1; R.rt.color[0] = &t; R.sc = (p_scissor){97,17,3,3};
    int x = lroundf(97*want), y = lroundf(17*want), w = lroundf(100*want)-x, h = lroundf(20*want)-y;
    CHECK(clear_rect_zero(0), "zero-clear fast path took the clear");
    mtl_sub_commit(); mtl_drain();
    expect_pixels(&t, mt, 0, x, y, w, h, 0);

    mtl_sub_begin();
    clear_color_tri(&(p_clear_color){.index=0, .mask=15, .rgba={1,0,0,1}});
    mtl_sub_commit(); mtl_drain();
    expect_pixels(&t, mt, 0, x, y, w, h, 0xff0000ff);

    mtl_sub_begin();
    p_clear_tex rect = whole; rect.r = (NVNcopyRegion){97,17,0,3,3,1}; rect.c.f[1] = 0; rect.c.f[0] = 0;
    clear_tex(&rect);
    mtl_sub_commit(); mtl_drain();
    expect_pixels(&t, mt, 0, x, y, w, h, 0xffff0000);

    size_t page = getpagesize();
    uint32_t *io = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    CHECK(io != MAP_FAILED, "buffer transfer pool allocated");
    if (io != MAP_FAILED) {
        mtl_pool_add(io, page);
        for (int i = 0; i < 9; i++) io[i] = 0xff00ff00;
        p_copy_b2t cp = {.src=(uint64_t)io, .tex=&t, .r={97,17,0,3,3,1}};
        mtl_sub_begin();
        copy_b2t(&cp, sizeof cp);
        cp.src = (uint64_t)(io + 32); copy_t2b(&cp, sizeof cp);
        mtl_sub_commit(); mtl_drain();
        expect_pixels(&t, mt, 0, x, y, w, h, 0xff00ff00);
        CHECK(!memcmp(io, io + 32, 9*4), "both GPU buffer transfers agree on the guest rectangle");
        mtl_pool_del(io); defer_drain(); munmap(io, page);
    }

    tex_t mip = target(76503, 192,108,5); mtl_tex_init(&mip);
    mtl_sub_begin();
    id<MTLTexture> mm = tex_mtl(&mip);
    p_clear_tex mc = {.tex=&mip, .has_view=1, .view={.set_levels=1,.base_level=3}, .r={0,0,0,24,13,1}, .mask=15, .c.f={1,0,0,1}};
    clear_tex(&mc);
    mtl_sub_commit(); mtl_drain();
    uint32_t last = 0;
    mtl_read_texels(&mip, 3, 0, &(NVNcopyRegion){23,12,0,1,1,1}, (uint8_t *)&last, 4, 4);
    CHECK(last == 0xff0000ff, "odd guest mip's bottom-right texel read back after full-level clear");
    CHECK(rs_rect(mc.r, rs_level(&mip, mm, 3)).height == (mm.height >> 3), "mapped mip rectangle spans the actual Metal mip");

    if ([g_dev supportsTextureSampleCount:4]) {
        tex_t ms = target(76504,192,108,1);
        ms.d.target = NVN_TEXTURE_TARGET_2D_MULTISAMPLE; ms.d.samples = 4;
        nvn_tex_layout(&ms.d, &ms.L); mtl_tex_init(&ms);
        mtl_sub_begin();
        p_clear_tex paint = {.tex=&ms, .r={0,0,0,192,108,1}, .mask=15, .c.f={1,1,0,1}};
        clear_tex(&paint);
        p_copy_t2t resolve = {.src=&ms, .dst=&t, .sr=paint.r, .dr=paint.r, .flags=DM_COPY_RESOLVE};
        CHECK(copy_t2t_enc(&resolve) == mt, "native MSAA resolves into the actual destination");
        mtl_sub_commit(); mtl_drain();
        uint32_t seen = 0;
        mtl_read_texels(&t, 0, 0, &(NVNcopyRegion){191,107,0,1,1,1}, (uint8_t *)&seen, 4, 4);
        CHECK(seen == 0xff00ffff, "resolve fills the scaled destination to its last pixel");
    }

    printf("Z-A render scale %g: %d failures\n", want, failed);
    return failed != 0;
} }
