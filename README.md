# ClipLite

ClipLite is a tiny native macOS clipboard history app built with Swift and AppKit.

It keeps the last few hours of clipboard text and small images, opens with `Command-Shift-V`, and lets you click an item to copy it back and paste into the app you were using.

## Features

- Native Swift + AppKit app, no Electron or background runtime.
- Global shortcut: `Command-Shift-V`.
- Simple clipboard history window near the mouse pointer with single-click selection.
- Text and small image support.
- Local-only history storage.
- Keeps at most 50 items from the last 6 hours.
- Ignores images larger than 5 MB.
- Polls the clipboard every 1 second using `NSPasteboard.changeCount`.
- Delays disk writes briefly to avoid writing on every rapid copy.
- Sizes the history window to the current item count and keeps it inside the visible screen area.

## Requirements

- macOS 13 or newer.
- Swift toolchain / Xcode command line tools.

Install command line tools if needed:

```zsh
xcode-select --install
```

## Build

```zsh
./scripts/build.sh
```

The app bundle will be created at:

```text
build/ClipLite.app
```

## Install

```zsh
./scripts/install.sh
```

This builds the app, installs it to:

```text
/Applications/ClipLite2.app
```

and launches it immediately.

## Usage

1. Copy text or a small image.
2. Press `Command-Shift-V`.
3. Click an item in the ClipLite window.

If Accessibility permission is granted, ClipLite will paste into the app that was active before the history window opened. If permission is not granted, ClipLite still copies the selected item to the system clipboard, and you can paste manually with `Command-V`.

## Accessibility Permission

macOS requires Accessibility permission for an app to synthesize `Command-V`.

Enable it here:

```text
System Settings > Privacy & Security > Accessibility
```

Add or enable:

```text
/Applications/ClipLite2.app
```

You do not need Accessibility permission for clipboard capture itself. It is only needed for automatic paste.

## Data Storage

ClipLite stores local history and logs here:

```text
~/Library/Application Support/ClipLite2/
```

Current files:

- `history.json`: recent clipboard history.
- `run.log`: lightweight local diagnostics.

History is local to your Mac. ClipLite does not sync, upload, or send clipboard content over the network.

## Uninstall

```zsh
./scripts/uninstall.sh
```

This removes:

- `/Applications/ClipLite.app`
- `/Applications/ClipLite2.app`
- `~/Library/Application Support/ClipLite`
- `~/Library/Application Support/ClipLite2`
- Accessibility entries for the old and current local bundle identifiers, when macOS allows reset.

## Development Notes

ClipLite intentionally stays small:

- Clipboard changes are detected by checking `NSPasteboard.changeCount`.
- The app only reads clipboard content after the change count changes.
- History is capped by time and count to keep memory and storage bounded.
- Large images are skipped to avoid surprise disk usage.

The current bundle identifier is:

```text
com.local.cliplite2
```

Building on macOS 14 or newer may show a deprecation warning for `activateIgnoringOtherApps`. This is related to returning focus to the previous app before sending `Command-V`; the current build still succeeds.

## License

No license has been selected yet. Add a license before publishing if you want others to reuse or modify the code.
