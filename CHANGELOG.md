# Changelog

## Unreleased

- Added a native macOS clipboard history app using Swift and AppKit.
- Added `Command-Shift-V` global shortcut.
- Added single-click selection and automatic paste.
- Added text and small image history.
- Added local JSON storage.
- Limited history to 50 items and 6 hours.
- Limited image history to 5 MB per image.
- Reduced background work with 1 second clipboard polling and delayed disk writes.
- Added install, build, and uninstall scripts.
- Positioned the history window near the mouse pointer with screen-edge clamping.
- Switched ClipLite back to menu bar utility mode so it does not show a Dock icon.
- Added outside-click dismissal for the history window.
- Added thumbnail previews for image history entries.
