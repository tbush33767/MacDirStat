# MacDirStat

A native macOS clone of [WinDirStat](https://windirstat.net): pick a disk (or
any folder), see where the space went, in the classic three-pane layout —

- **Directory tree** (top left): every folder and file with size, subtree-percentage
  bar, item/file/folder counts, and last-change date. Sortable by any column.
- **Extension list** (top right): total bytes, share, and file count per file
  extension, with the color swatch used in the treemap.
- **Cushion treemap** (bottom): every file is a shaded rectangle proportional
  to its on-disk size, colored by extension — the signature WinDirStat visual
  (van Wijk cushion shading, squarified layout).

All three panes are linked: click a treemap tile and the tree expands to that
file and its extension highlights; select an extension and every matching tile
is outlined; arrow through the tree and the selection frame follows in the map.

The start screen lists mounted disks WinDirStat-style — usage bar, capacity,
and free space per volume — with a folder-scan option for narrower digs; the
toolbar's disk menu switches targets later. After a whole-disk scan the status
bar shows the volume's free/total space alongside the scan totals.

Scanning the system disk handles Apple's split-volume layout correctly: the
Data volume's contents are counted once through the firmlinked paths
(`/Users`, `/Applications`, …) and its raw mount at `/System/Volumes/Data` is
stubbed out, so nothing is double-counted.

Actions: **Reveal in Finder**, **Open**, and **Move to Trash** (confirmation
first; uses the Finder trash, so Put Back works). After a delete the tree,
extension stats, and treemap update in place — no rescan.

## Building

No Xcode project is involved. The Swift 6.2 Command Line Tools
(`xcode-select --install`) are enough.

> **macOS 27 SDK:** the Command Line Tools build fails with
> `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found`.
> That SDK implements SwiftUI's `@State` as a macro, and its plugin ships only with
> full Xcode. Install Xcode and select it before building:
> `sudo xcode-select -s /Applications/Xcode.app`

```sh
./build.sh   # release build + assembles dist/MacDirStat.app (ad-hoc signed)
./run.sh     # build + launch
./test.sh    # run the unit test suite
```

`swift run MacDirStat` also works for quick iteration, but menu-bar naming and
disk permissions are only correct when launched from the bundle.

There is also a CLI harness for benchmarking the scanner:

```sh
swift run -c release MacDirStatCLI ~/Documents
```

### Why test.sh?

The CLT ships `Testing.framework`, but SwiftPM passes its directory as `-I`
instead of `-F`, and the `_Testing_Foundation` cross-import overlay is missing
its Swift module files. `test.sh` adds the right flags. Plain `swift test`
works fine if you have full Xcode installed.

## Permissions (macOS TCC)

The app is not sandboxed, but macOS still gates certain folders. There is no
API for an app to elevate itself past this — the one-grant fix is **Full Disk
Access**, so when it's missing MacDirStat offers to take you to the right
Settings pane before a scan (suppressible via "Don't ask again").

- Scanning **Desktop / Documents / Downloads** triggers a one-time system
  permission prompt per folder.
- **~/Library/Mail**, **Photos libraries**, Time Machine snapshots, etc.
  require **Full Disk Access** (System Settings → Privacy & Security → Full
  Disk Access → add `dist/MacDirStat.app`).
- Folders the app can't read are kept in the tree, shown dimmed with a 🔒,
  and counted in the status bar ("N unreadable").

### Why signing matters for Full Disk Access

`build.sh` signs the app with a **stable self-signed certificate** (created
once in your login keychain by `Support/signing-identity.sh`), not an ad-hoc
signature. This is deliberate: an ad-hoc signature gives TCC only a per-build
`cdhash` to key grants against, so macOS shows Full Disk Access as "on" but
does **not** honor it at runtime — the app re-prompts forever. The self-signed
cert produces a stable designated requirement (`identifier "com.tyler.MacDirStat"
and certificate leaf = …`) that depends on the cert and bundle id, so a single
Full Disk Access grant persists across app relaunches **and** rebuilds.

The app detects whether it actually has Full Disk Access (by test-reading a
TCC-protected path) and only shows the grant prompt when it genuinely lacks
access — so once granted, it never asks again.

Gatekeeper (`spctl`) will "reject" the self-signed app; that's expected and
irrelevant for a locally-built app you launch yourself. If the login keychain
is ever reset, `build.sh` recreates the cert with a new hash — grant Full Disk
Access once more after that.

## Implementation notes

- **Scanner** (`MacDirStatCore/ScanEngine.swift`): `getattrlistbulk(2)` —
  batches of directory entries with attributes per syscall; ~75–200k items/s
  on APFS. Symlinks are never followed; hard links are counted once (tracked
  by file ID); volume boundaries are not crossed. Runs on a dedicated thread
  with a 16 MB stack (recursion depth = filesystem depth).
- **Treemap** (`TreemapLayout.swift`, `CushionRenderer.swift`): squarified
  layout per directory with a 3 px cutoff, then per-pixel parabolic cushion
  shading into an RGBA buffer off the main thread (WinDirStat's parameters:
  h = 0.75, f = 0.75). Selection and extension highlights are separate
  `CAShapeLayer`s, so selecting never re-renders the bitmap.
- **Directory tree**: `NSOutlineView` wrapped in `NSViewRepresentable` — lazy
  sorted-children cache, custom percent-bar cell, programmatic
  expand-and-reveal for treemap→tree cross-linking.
- Sizes shown are **on-disk** (allocated) sizes, so APFS compression and
  sparse files are reflected honestly; logical sizes are also tracked.
- Zero third-party dependencies.

## Layout

```
Sources/MacDirStatCore/   scan engine, treemap math, palette (no AppKit)
Sources/MacDirStat/       SwiftUI app, AppKit-backed panes
Sources/MacDirStatCLI/    scanner benchmark/test harness
Tests/                    squarify invariants, cushion math, scan fixtures
Support/                  Info.plist, icon generator
```
