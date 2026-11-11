// Built-in code mods switch together; RomFS folders and unrelated directories do not turn them on.
#include "../hle_mods.c"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

static void make(const char *path) {
    char command[1400]; snprintf(command, sizeof command, "mkdir -p '%s'", path); assert(!system(command));
}
static void code(const char *root, const char *name) {
    char dir[1100], path[1200]; snprintf(dir, sizeof dir, "%s/%s", root, name); make(dir);
    snprintf(path, sizeof path, "%s/dm_code.tsv", dir); FILE *f = fopen(path, "w"); assert(f); fputs("patch.pchtxt\n", f); fclose(f);
}

int main(void) {
    const char *root = "build/mods-fixture"; make(root); code(root, "One"); code(root, "Two");
    char romfs[1100]; snprintf(romfs, sizeof romfs, "%s/Files/romfs", root); make(romfs);
    assert(!setenv("DM_MODS", root, 1)); unsetenv("DM_ROOT"); unsetenv("DM_MODS_OFF");
    assert(dm_mods_code_wanted());
    assert(!setenv("DM_MODS_OFF", "Two", 1)); assert(!dm_mods_code_wanted());
    assert(!setenv("DM_MODS_OFF", "Other", 1)); assert(dm_mods_code_wanted());
    assert(!setenv("DM_MODS_OFF", "One/Two", 1)); assert(!dm_mods_code_wanted());
    assert(!setenv("DM_ROOT", root, 1)); unsetenv("DM_MODS"); unsetenv("DM_MODS_OFF");
    assert(!dm_mods_code_wanted());   // DM_ROOT names the parent of mods, not the mods folder itself
    assert(!setenv("DM_MODS", "build/mods-missing", 1)); assert(!dm_mods_code_wanted());
    puts("mods ok"); return 0;
}
