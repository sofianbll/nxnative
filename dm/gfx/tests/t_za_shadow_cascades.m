// Exercise the Metal helper with the host's real support buffer, using only synthetic cascade matrices.
#include "../nvn/nvn_mtl.m"
#include <assert.h>

void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }

int main(int argc, char **argv) { @autoreleasepool {
    assert(argc == 3);
    mtl_init();
    const int enabled = !strcmp(argv[2], "1");
    NSError *e = nil;
    NSString *src = [NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:&e];
    assert(src);
    id<MTLLibrary> lib = [g_dev newLibraryWithSource:src options:nil error:&e];
    assert(lib || (fprintf(stderr, "%s\n", e.localizedDescription.UTF8String), 0));
    id<MTLComputePipelineState> ps = [g_dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"check"] error:&e];
    assert(ps);
    id<MTLBuffer> matrices = [g_dev newBufferWithLength:192 options:MTLResourceStorageModeShared],
                  output = [g_dev newBufferWithLength:48 options:MTLResourceStorageModeShared];
    id<MTLCommandQueue> q = [g_dev newCommandQueue];
    for (int test = 0; test < 5; test++) {
        float *m = matrices.contents;
        memset(m, 0, matrices.length);
        for (int i = 0; i < 48; i += 16) m[i] = m[i + 5] = m[i + 10] = m[i + 15] = 1;
        m[16] = .5f; m[21] = .25f;
        m[32] = 2; m[37] = .125f;   // clamp widening only on x
        if (test == 1) m[31] = 2;     // homogeneous divisor
        if (test == 2) m[19] = .25f;  // perspective
        if (test == 3) m[16] = NAN;
        if (test == 4) m[16] = 0;     // degenerate axis
        id<MTLCommandBuffer> cb = [q commandBuffer];
        id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder];
        [ce setComputePipelineState:ps];
        [ce setBuffer:matrices offset:0 atIndex:0];
        [ce setBuffer:support_buf() offset:0 atIndex:1];
        [ce setBuffer:output offset:0 atIndex:2];
        [ce dispatchThreads:MTLSizeMake(6, 1, 1) threadsPerThreadgroup:MTLSizeMake(6, 1, 1)];
        [ce endEncoding]; [cb commit]; [cb waitUntilCompleted];
        assert(cb.status == MTLCommandBufferStatusCompleted);
        const float *r = output.contents;
        const float x = enabled && test < 2 ? (test ? .25f : .5f) : 1.0f, y = enabled && test < 2 ? (test ? .125f : .25f) : 1.0f;
        assert(r[2] == x && r[3] == y && r[4] == 1 && r[5] == (enabled ? .125f : 1.0f));
        assert(r[0] == 1 && r[1] == 1);   // nearest
        for (unsigned i = 6; i < 12; i++) assert(r[i] == 1);   // invalid layer, short uniform, wrong array
    }
    printf("Z-A shadow cascades (%s): five Metal cases passed\n", enabled ? "on" : "off");
    return 0;
} }
