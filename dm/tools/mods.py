"""Code mods for a Mac app build (scripts/build_ipa_from_nsp.py --mods): find their ExeFS patches and stage the switch metadata.

A mod is a folder with exefs/ (code patches, .pchtxt or .ips: exefs_mods.py), optionally beside romfs/. A folder given may be a mod itself, a folder of mods,
an exefs_patches/<mod> folder of patch files, or one of the Atmosphère, Ryujinx and yuzu trees downloads come in. Replacement modules are not supported.
RomFS files stay the front end's DM_ROMFS_OVERLAY business: only dm_code.tsv goes into the app, so its loader can switch the rewritten code without applying
those files a second time.
"""
import os
import shutil
from pathlib import Path

PATCH_EXT = ('.pchtxt', '.ips')


class Mod:
    def __init__(self, name, folder, exefs=None):
        self.name, self.dir = name, Path(folder)
        self.romfs = self.dir / 'romfs' if (self.dir / 'romfs').is_dir() and any(_files(self.dir / 'romfs')) else None
        ex = Path(exefs) if exefs else self.dir / 'exefs'
        files = sorted(_files(ex)) if ex.is_dir() else []
        self.patches = [p for p in files if p.suffix.lower() in PATCH_EXT]
        self.other = [p for p in files if p.suffix.lower() not in PATCH_EXT]

    def __repr__(self): return f'Mod({self.name!r}, {self.dir})'


def _files(d):
    for root, dirs, names in os.walk(d):
        dirs[:] = [x for x in dirs if not x.startswith('.')]
        for n in names:
            if not n.startswith('.'): yield Path(root) / n


def _child_ci(d, name):
    try: return next((p for p in Path(d).iterdir() if p.name.lower() == name.lower() and p.is_dir()), None)
    except OSError: return None


def _is_mod(d): return (Path(d) / 'romfs').is_dir() or (Path(d) / 'exefs').is_dir()


def _patch_folder(d): return Path(d).is_dir() and any(p.suffix.lower() in PATCH_EXT for p in Path(d).iterdir() if p.is_file())


def _subdirs(d): return sorted((p for p in Path(d).iterdir() if p.is_dir() and not p.name.startswith('.')), key=lambda p: p.name)


def _tree(name, base, tid):
    """the mods of the trees under base; [] when it has none"""
    out = []
    atm = _child_ci(base, 'atmosphere')
    t = _child_ci(_child_ci(atm, 'contents'), tid) if atm and _child_ci(atm, 'contents') else None
    if t and _is_mod(t): out.append(Mod(name, t))
    ep = _child_ci(atm, 'exefs_patches') if atm else _child_ci(base, 'exefs_patches')
    if ep: out += [Mod(s.name, s, exefs=s) for s in _subdirs(ep) if _patch_folder(s)]
    c = _child_ci(base, 'contents')
    for t in filter(None, (_child_ci(c, tid) if c else None, _child_ci(base, tid))):
        out += [Mod(name, t)] if _is_mod(t) else [Mod(s.name, s) for s in _subdirs(t) if _is_mod(s)]
    return out


def find(folder, tid, _depth=0):
    """the mods in a folder given to --mods (see the module's note), in name order within a folder of mods"""
    p = Path(folder).expanduser()
    if not p.is_dir(): raise FileNotFoundError(f'no mod folder {p}')
    if _is_mod(p): return [Mod(p.name, p)]
    if _patch_folder(p): return [Mod(p.name, p, exefs=p)]
    got = _tree(p.name, p, tid)
    if got or _depth: return got
    return [m for s in _subdirs(p) for m in find(s, tid, 1)]


def stage(mods, applied, out):
    """write out/<name>/dm_code.tsv for each mod whose code patches went into the build, with no RomFS copy. Returns [(name, patch files applied)]"""
    if out.exists(): shutil.rmtree(out)
    out.mkdir(parents=True)
    rows = []
    for m in mods:
        mine = [p for p in m.patches if str(p) in applied]
        if not mine: continue
        d = out / m.name; d.mkdir()
        (d / 'dm_code.tsv').write_text('# code patches in the app\'s codemods copy of the modules (scripts/build_ipa_from_nsp.py --mods): on with the other code mods\n' + ''.join(f'{p.name}\n' for p in mine))
        rows.append((m.name, len(mine)))
    return rows


def applied_files(patched):
    """the patch files the rewriter applied to any module in the patched folder (<module>.mods.tsv)"""
    out = set()
    for t in Path(patched).glob('*.mods.tsv'):
        for ln in t.read_text(encoding='utf-8').splitlines():
            if ln and not ln.startswith('#'): out.add(ln.split('\t')[3])
    return out
