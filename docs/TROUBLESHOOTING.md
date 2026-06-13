# Troubleshooting

## The shortcut does not open ClipLite

Check whether ClipLite is running:

```zsh
pgrep -fl 'ClipLite|ClipLite2'
```

If it is not running, launch it:

```zsh
open /Applications/ClipLite2.app
```

If another app already owns `Command-Shift-V`, ClipLite may not be able to register the shortcut. Quit or change the conflicting app and restart ClipLite.

## ClipLite copies but does not auto-paste

This means macOS has not granted Accessibility permission to ClipLite.

Open:

```text
System Settings > Privacy & Security > Accessibility
```

Make sure `/Applications/ClipLite2.app` is enabled. If there is an old `ClipLite.app` entry, remove or disable it so the current app is not confused with the old one.

## Reset Accessibility Permission

If macOS says permission is granted but auto-paste still fails, try:

```zsh
tccutil reset Accessibility com.local.cliplite2
```

Then open ClipLite again and grant permission to `/Applications/ClipLite2.app`.

## Check Logs

ClipLite writes a small local log here:

```zsh
tail -n 80 "$HOME/Library/Application Support/ClipLite2/run.log"
```

Useful log lines:

- `hotkey_registered=true`: the global shortcut was registered.
- `window_visible_after=true`: the history window opened.
- `accessibility_missing copied_only`: selected item was copied, but automatic paste was blocked by macOS permission.
- `send_paste_command`: ClipLite attempted to send `Command-V`.
- `skip_large_image`: an image was larger than the configured 5 MB history limit.

