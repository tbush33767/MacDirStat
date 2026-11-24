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

## Install

1. Download **`MacDirStat-1.0.dmg`** from the
   [latest release](https://github.com/tbush33767/MacDirStat/releases/latest).
2. Open the DMG and drag `MacDirStat.app` onto the `Applications` shortcut.
3. Eject the disk image.

**Requirements:** Apple silicon (arm64 only) and macOS 15 or later.

### First launch

The app is signed with a self-signed certificate, not an Apple Developer ID,
and it is not notarized, so Gatekeeper blocks the first launch. macOS 15
removed the old Control-click → Open shortcut, so use one of these instead
(only needed once):

- **Either** clear the quarantine flag before opening it:

  ```sh
  xattr -dr com.apple.quarantine /Applications/MacDirStat.app
  ```

- **Or** double-click the app, dismiss the "not opened" dialog, then go to
  System Settings → Privacy & Security, scroll to Security, click
  **Open Anyway**, and authenticate.

## Permissions (macOS TCC)

The app is not sandboxed, but macOS still gates certain folders. There is no
API for an app to elevate itself past this — the one-grant fix is **Full Disk
Access**, so when it's missing MacDirStat offers to take you to the right
Settings pane before a scan (suppressible via "Don't ask again").

- Scanning **Desktop / Documents / Downloads** triggers a one-time system
  permission prompt per folder.
- **~/Library/Mail**, **Photos libraries**, Time Machine snapshots, etc.
  require **Full Disk Access** (System Settings → Privacy & Security → Full
  Disk Access → add `/Applications/MacDirStat.app`).
- Folders the app can't read are kept in the tree, shown dimmed with a 🔒,
  and counted in the status bar ("N unreadable").

The app checks whether it actually has Full Disk Access and only prompts when
it genuinely lacks it, so once granted it never asks again.
