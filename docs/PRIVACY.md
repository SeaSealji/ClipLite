# Privacy

ClipLite is local-only.

It does not make network requests, does not sync clipboard data, and does not upload clipboard content.

Clipboard history is stored on disk at:

```text
~/Library/Application Support/ClipLite2/history.json
```

Diagnostic logs are stored at:

```text
~/Library/Application Support/ClipLite2/run.log
```

History retention:

- Up to 50 items.
- Up to 6 hours.
- Images larger than 5 MB are ignored.

Automatic paste requires macOS Accessibility permission because ClipLite sends a synthetic `Command-V` event after you select a history item.

