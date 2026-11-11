// Code mods built into a Mac app (hle_mods.c). The front end keeps RomFS overlays separate.
#pragma once

int dm_mods_code_wanted(void);   // at least one built-in code mod, and none switched off through DM_MODS_OFF
