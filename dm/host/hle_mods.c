// Code mods staged by build_ipa_from_nsp.py --mods. Each <DM_MODS>/<name>/dm_code.tsv marks patches present in the modules' codemods copy.
// One copy holds every code mod, so they switch together: DM_MODS_OFF=<name>[/<name>…] turns the whole copy off when any one is off.
// RomFS is deliberately absent here. NX2Apple passes enabled romfs/ folders through DM_ROMFS_OVERLAY, as it did before code mods.
#include "mods.h"
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int switched_off(const char *name) {
    const char *off = getenv("DM_MODS_OFF"); size_t k = strlen(name);
    for (const char *s = off; s && *s; ) {
        const char *t = strchr(s, '/'); size_t len = t ? (size_t)(t - s) : strlen(s);
        if (len == k && !strncmp(s, name, k)) return 1;
        s = t ? t + 1 : NULL;
    }
    return 0;
}

int dm_mods_code_wanted(void) {
    char def[1100]; const char *e = getenv("DM_MODS");
    if (!e || !*e) { const char *r = getenv("DM_ROOT"); if (!r || !*r) return 0; snprintf(def, sizeof def, "%s/mods", r); e = def; }
    char *all = strdup(e), *save = NULL; if (!all) abort();
    int any = 0;
    for (char *root = strtok_r(all, ":", &save); root; root = strtok_r(NULL, ":", &save)) {
        DIR *d = opendir(root); if (!d) continue;
        struct dirent *ent;
        while ((ent = readdir(d))) {
            if (ent->d_name[0] == '.') continue;
            char p[1200]; snprintf(p, sizeof p, "%s/%s/dm_code.tsv", root, ent->d_name);
            if (access(p, F_OK)) continue;
            any = 1;
            if (switched_off(ent->d_name)) { closedir(d); free(all); return 0; }
        }
        closedir(d);
    }
    free(all);
    return any;
}
