# Nextendo BCAT delivery

### Online sync fails before the delivery cache opens

- **Symptom:** Pokémon Legends: Z-A 2.0.2 calls `RequestSyncDeliveryCache`, then reports `0x2a2` (`2162-0001`) without polling progress or opening a delivery file.

- **Cause:** the host only knew the signed Splatoon 2 calendar recipe. For titles without that recipe it rejected the sync request even though Nextendo published delivery files.

- **Fix:** an explicit `DM_NETWORK=nextendo` launch with valid routes and a title-matched service manifest with `bcat: true` checks the public `GET /api/bcat/<base-title-id>` before guest startup, with system HTTPS trust and the existing 12-second budget. Build or regenerate the service profile with `--nextendo` to acquire the flag. See the [Nextendo BCAT guide](https://wiki.nextendo.network/bcat#bc-http): the guest sees plain `<directory>/<file>` paths (ASCII names up to 31 characters), sizes and 16-byte MD5 digests, not the console's BCAT containers. The public ZIP route presently has no `ETag`: compare the ZIP's SHA-256 and keep identical content in place. When a validator is supplied, the host sends `If-None-Match`; `304`, `204`, errors and invalid ZIPs keep the previous validated cache. Scarlet can retry Violet's package on `204` or `404`; the caches remain separate.

The host limits the download to 8 MiB and extraction to 512 files, 8 MiB per file and 32 MiB total. It publishes the complete replacement atomically under `~/Library/Application Support/nxnative/<TITLEID>/bcat-nextendo/` (0700). Existing launches can finish using their old generation, so old generations are not pruned. The `bcat:` mount and SDK enumeration use the selected files; guest sync completes immediately (`Done`/9, result 0) when those files exist, and fails otherwise. Generic packages are not used offline, take no RomFS overlay, and do not make guest-time requests. A configured signed Splatoon 2 recipe retains precedence and its existing behavior.

- **Found on:** [Pokémon Legends: Z-A](../../dm/games/0100F43008C44000/README.md). A synthetic host test exercises startup, refresh/fallback and SDK reads; online gameplay still needs verification.

## Signed Splatoon 2 calendar recipe

I separated this backend from my application's interface for the [online-service scope discussion](https://github.com/seedds/nxnative/issues/951). I keep the service interfaces independent of an account or authorization UI. I have not established gameplay on this newly based upstream branch.

### Startup and offline behavior

`main.c` calls `dm_bcat_pre_guest_start` on the guest boot thread, before SDK initialization and the game's first filesystem read. The weak `dm_bcat_online_enabled()` provider returns zero. A configured online-service backend may override it only after checking explicit online mode and a valid local service profile. That capability does not authenticate a calendar: the signed catalog and content checks remain mandatory.

I require a separate exact-title/version recipe, `bcat/setup.json` beside the modules or under `DM_NEXTENDO_BCAT_DIR`. No recipe, an invalid title/version, an absent online provider, or a build without the optional signature verifier causes **zero HTTP requests**. An offline launch may select a previously validated bundled or private cached snapshot; missing data remains unavailable. I do not report an empty delivery mount or a disabled synchronization as successful delivery. Oodle helper modes do not initialize calendars.

Every online process checks again, even if another launch just refreshed the cache. I use one **12-second monotonic network budget** across the catalog, archive and optional static requests. Failure or timeout retains the last validated snapshot and reports freshness as unconfirmed. Later guest sync requests use an actual background job; observers retain that job's lifetime, status, result and byte count. A later successful job changes future delivery opens, while the RomFS overlay stays fixed for the current game session.

### Validation and storage

I verify canonical Base64 and Ed25519 signatures, reject duplicate JSON fields and unknown required capabilities, enforce catalog identity, time bounds, revision/issue rollback rules, title eligibility and accepted versions. Verification uses the shared static OpenSSL prefix under `DM_OPENSSL_X509`; without that capability I reject catalogs and cached snapshots. This branch does not add or download a cryptography implementation. The separate TLS/online series supplies its reviewed static library and licenses.

The first provider recipe supports only Splatoon 2's three regional IDs and **5.5.2**. This is a recipe boundary, not a compatibility claim for all three executables. The calendar ZIP is unsigned: I require normal HTTPS authentication and use the signed game catalog for eligibility, not as a signature over archive bytes. I pin static recipe resources by public commit and SHA-256.

I bound downloads, entry counts and expanded sizes; reject redirects, encryption, unsupported compression, traversal, duplicate/case-alias names, symlinks and overlapping/local-versus-central inconsistencies; verify CRCs and required resource structures. Published snapshots contain their signed catalog, provenance and per-file hashes. I serialize publication under a nonblocking interprocess lock and atomically replace the current pointer only after complete validation. I do not prune a running session's referenced snapshot. Atomic visibility and file synchronization do not constitute a separately tested whole-directory power-loss transaction.

`hle_fs.c` merges the selected immutable overlay read-only with existing RomFS overlays and mounts real delivery files at `bcat:`. Unmount hides new path opens while already opened file descriptors remain valid. SDK delivery objects retain their own files, directory snapshots and synchronization observers. `GetDigest` returns the actual 16-byte MD5 value in both AAPCS64 return registers through the existing large-stack entry; the digest is not an authentication signature.

The preparation API in `dm/tools/nextendo_bcat.py` writes an exact recipe, invokes the same native verifier and stages one complete validated snapshot. A deliberately recipe-only offline seed is explicitly incomplete; it is never promoted into successful delivery. The tool requires `DM_OPENSSL_ROOT`, and its private helper/cache belongs under `Library/Application Support/nxnative/BCAT`, not the source tree. I include no real calendar archive, game resource, SDK, firmware, account credential or enrolled certificate.

### Checks and limits

I ran the native signed-policy/store, bounded ZIP, SDK lifetime/ABI and real temporary-filesystem fixtures in normal and ASan/UBSan builds. The synthetic downloader exercises 20 new-process scenarios, including changed data before the first open, ETag/304, responses without ETags, shared timeout, interruption, cache preservation, all zero-request gates, a separately linked online-provider override and a real background refresh that preserves the session overlay and old open descriptor while advancing delivery opens. These fixtures use original resource bytes, fixture-only signing keys and isolated temporary home directories; they never contact a provider or use the account/cache of the person running them.

```sh
make -C dm/host/tests GAME=0100152000022000 DM_OPENSSL_ROOT='/reviewed/static/openssl' bcat bcat-sanitize
DM_BCAT_TEST_SANITIZE=1 make -C dm/host/tests GAME=0100152000022000 DM_OPENSSL_ROOT='/reviewed/static/openssl' bcat-launch
```

In my originating fork I tested real calendar refresh and Splatoon 2 EUR 5.5.2 reaching the Mac online lobby and Territorial queue. I deferred the match test because too few players were available during my attempt. That does not qualify this rebased branch, a completed match, peer-to-peer play, another title/region or iOS gameplay. I have not run new hardware/game regression sessions for this extraction; their absence remains explicit before a final upstream submission.
