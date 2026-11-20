// Mount synthetic Trinity archives through the guest file hooks, without any game files.
#include "../hle_fs.c"
#include <assert.h>

struct dm_flags g_flag;
uint64_t g_t0_ns;
uint64_t now_ns(void) { return 0; }
void dm_guest_write_prepare(void *p, size_t n) { (void)p; (void)n; }

enum { DESC_SIZE = 352 };
static void put16(uint8_t *p, uint16_t n) { memcpy(p, &n, 2); }
static void put32(uint8_t *p, uint32_t n) { memcpy(p, &n, 4); }
static void put64(uint8_t *p, uint64_t n) { memcpy(p, &n, 8); }
static void descriptor(uint8_t *d) {
    // Root holds four vectors and an unknown scalar; vector 2 points to four distinct file tables.
    const uint16_t root_vt[] = {18, 24, 4, 8, 12, 16, 0, 0, 20};
    const uint16_t file_vt[] = {8, 16, 8, 4}, sub_vt[] = {6, 8, 4}, pack_vt[] = {8, 24, 8, 16};
    // Game Freak FNV-1a of effects/{A,Keep,B,Last}.bin respectively, calculated independently.
    const uint64_t hashes[] = {0x198e50f4070da302ull, 0x9d719ba4cce32d14ull, 0xd1e249e45171db1bull, 0xf224ffc2c6d73bedull};
    put32(d, 24); memcpy(d + 4, root_vt, sizeof root_vt); put32(d + 24, 20);
    put32(d + 28, 52 - 28); put32(d + 32, 88 - 32);
    put32(d + 36, 100 - 36); put32(d + 40, 120 - 40); put32(d + 44, 0xfedcba98);
    put32(d + 52, 4); memcpy(d + 56, hashes, sizeof hashes);
    put32(d + 88, 2); put32(d + 92, 132 - 92); put32(d + 96, 144 - 96);
    put32(d + 100, 4);
    put32(d + 120, 2); put32(d + 124, 304 - 124); put32(d + 128, 328 - 128);
    put32(d + 132, 3); memcpy(d + 136, "one", 4);
    put32(d + 144, 3); memcpy(d + 148, "two", 4);
    memcpy(d + 152, file_vt, sizeof file_vt); memcpy(d + 248, sub_vt, sizeof sub_vt);
    for (unsigned i = 0; i < 4; i++) {
        unsigned at = 104 + 4 * i, file = 160 + 16 * i, sub = 256 + 8 * i;
        put32(d + at, file - at);
        put32(d + file, file - 152); put32(d + file + 4, sub - file - 4); put64(d + file + 8, i / 2);
        put32(d + sub, sub - 248); put32(d + sub + 4, 90 + i);
    }
    memcpy(d + 296, pack_vt, sizeof pack_vt);
    put32(d + 304, 8); put64(d + 312, 12345); put64(d + 320, 2);
    put32(d + 328, 32); put64(d + 336, 67890); put64(d + 344, 2);
}
static void write_fixture(const char *root, const char *rel, const void *bytes, size_t n) {
    char path[1024];
    assert(snprintf(path, sizeof path, "%s/%s", root, rel) < (int)sizeof path);
    if (!bytes) { assert(!mkdir(path, 0700)); return; }
    FILE *f = fopen(path, "wb");
    assert(f && fwrite(bytes, 1, n, f) == n && !fclose(f));
}
static void image(const char *root, const uint8_t *base) {
    // DMROMFS1 with /arc/data.trpfd as its only file.
    uint8_t raw[32 + DESC_SIZE + 3 * sizeof(img_ent) + 13] = {0};
    img_ent entries[] = {{1, 1, 0, 0, 0, 0}, {2, 1, 0, 3, 0, 0}, {32, DESC_SIZE, 3, 10, 1, 0}};
    memcpy(raw, "DMROMFS1", 8);
    put64(raw + 8, 32 + DESC_SIZE); put64(raw + 16, sizeof entries + 13); put64(raw + 24, 3);
    memcpy(raw + 32, base, DESC_SIZE);
    memcpy(raw + 32 + DESC_SIZE, entries, sizeof entries);
    memcpy(raw + 32 + DESC_SIZE + sizeof entries, "arcdata.trpfd", 13);
    write_fixture(root, "base.img", raw, sizeof raw);
}
static void expect_file(const char *path, const void *want, size_t n) {
    uint64_t h = 0; int64_t size; size_t got;
    uint8_t data[DESC_SIZE + 1];
    assert(n && n < sizeof data);
    assert(h_fs_OpenFile(&h, path, MODE_READ) == RES_OK);
    assert(h_fs_GetFileOpenMode(h) == MODE_READ);
    assert(h_fs_GetFileSize(&size, h) == RES_OK && size == (int64_t)n);
    assert(h_fs_ReadFile(&got, h, 0, data, sizeof data) == RES_OK && got == n && !memcmp(data, want, n));
    assert(h_fs_ReadFile(&got, h, 1, data, sizeof data) == RES_OK && got == n - 1 && !memcmp(data, (const uint8_t *)want + 1, got));
    assert(h_fs_ReadFile(&got, h, (int64_t)n, data, sizeof data) == RES_OK && got == 0);
    h_fs_CloseFile(h);
}
int main(void) {
    const char *tmp = getenv("TMPDIR");
    char root[1024], rom[1100], mods[2200];
    assert(snprintf(root, sizeof root, "%s/t_fs_trpfd.XXXXXX", tmp ? tmp : "/private/tmp") < (int)sizeof root && mkdtemp(root));
    const char *dirs[] = {"base", "base/arc", "mod1", "mod1/arc", "mod1/effects", "mod2", "mod2/effects", "pack", "pack/arc"};
    for (size_t i = 0; i < sizeof dirs / sizeof *dirs; i++) write_fixture(root, dirs[i], NULL, 0);
    uint8_t base[DESC_SIZE] = {0}, want[DESC_SIZE]; descriptor(base); memcpy(want, base, sizeof want);
    put32(want + 52, 2); put32(want + 100, 2);
    memcpy(want + 56, base + 64, 8); memcpy(want + 64, base + 80, 8);
    put32(want + 104, 176 - 104); put32(want + 108, 208 - 108);
    write_fixture(root, "base/arc/data.trpfd", base, sizeof base);
    image(root, base);
    write_fixture(root, "mod1/arc/data.trpfd", "first", 5);
    write_fixture(root, "mod1/effects/A.bin", "upper", 5);
    write_fixture(root, "mod2/effects/A.bin", "lower", 5);
    write_fixture(root, "mod2/effects/B.bin", "second", 6);
    write_fixture(root, "pack/arc/data.trpfs", "pack", 4);

    snprintf(rom, sizeof rom, "%s/base", root); assert(!setenv("DM_ROMFS", rom, 1));
    snprintf(mods, sizeof mods, "%s/mod1:%s/mod2", root, root);
    assert(!setenv("DM_ROMFS_OVERLAY", mods, 1) && !unsetenv("DM_TRPFD_MERGE"));
    assert(h_fs_MountRom("rom", NULL, 0) == RES_OK);
    assert(h_fs_MountRom("rom", NULL, 0) == RES_OK);   // no re-merge on a repeated mount
    expect_file("rom:/effects/A.bin", "upper", 5);
    expect_file("rom:/effects/B.bin", "second", 6);
    if (DM_GAME_TRPFD_MERGE) {
        expect_file("rom:\\arc\\data.trpfd", want, sizeof want);
        uint64_t h = 0;
        assert(h_fs_OpenFile(&h, "rom:/arc/data.trpfd", MODE_WRITE) == RES_FAIL && !h);
        snprintf(rom, sizeof rom, "%s/base.img", root); assert(!setenv("DM_ROMFS", rom, 1));
        assert(h_fs_MountRom("image", NULL, 0) == RES_OK);
        expect_file("image:/arc/./data.trpfd", want, sizeof want);
        memcpy(want, base, sizeof want);
        put32(want + 52, 3); put32(want + 100, 3);
        memcpy(want + 56, base + 64, 24);
        put32(want + 104, 176 - 104); put32(want + 108, 192 - 108); put32(want + 112, 208 - 112);
        snprintf(mods, sizeof mods, "%s/mod1", root); assert(!setenv("DM_ROMFS_OVERLAY", mods, 1));
        assert(h_fs_MountRom("single", NULL, 0) == RES_OK);
        expect_file("single:/arc/data.trpfd", want, sizeof want);

        assert(!setenv("DM_TRPFD_MERGE", "0", 1));
        assert(h_fs_MountRom("off", NULL, 0) == RES_OK);
        expect_file("off:/arc/data.trpfd", "first", 5);
        assert(!unsetenv("DM_TRPFD_MERGE"));
        snprintf(mods, sizeof mods, "%s/mod1:%s/pack", root, root);
        assert(!setenv("DM_ROMFS_OVERLAY", mods, 1));
        assert(h_fs_MountRom("pack", NULL, 0) == RES_OK);
        expect_file("pack:/arc/data.trpfd", "first", 5);
        expect_file("pack:/arc/data.trpfs", "pack", 4);

        // A bad uoffset in a pair that would be removed is still a parse failure.
        put32(base + 104, UINT32_MAX - 3);
        write_fixture(root, "base/arc/data.trpfd", base, sizeof base);
        snprintf(rom, sizeof rom, "%s/base", root); assert(!setenv("DM_ROMFS", rom, 1));
        snprintf(mods, sizeof mods, "%s/mod1:%s/mod2", root, root);
        assert(!setenv("DM_ROMFS_OVERLAY", mods, 1));
        assert(h_fs_MountRom("bad", NULL, 0) == RES_OK);
        expect_file("bad:/arc/data.trpfd", "first", 5);
    } else expect_file("rom:/arc/data.trpfd", "first", 5);
    assert(!rm_tree(root));
    puts("fs trpfd ok");
    return 0;
}
