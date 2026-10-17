# Contributing to ShiTie / 参与拾贴

欢迎使用中文或英文反馈问题、提出建议和提交代码。Chinese and English contributions are welcome.

## Before you start

Search existing [issues](https://github.com/wangleijie5859/ShiTie/issues) before opening a new one. For larger changes, describe the problem and proposed behavior in an issue first so the scope can be discussed.

Bug reports should include macOS and app versions, chip architecture, steps to reproduce, expected behavior, and actual behavior. Use synthetic text when sharing screenshots or logs. Do not attach clipboard databases, passwords, tokens, or personal clipboard contents.

Security reports belong in [private vulnerability reporting](SECURITY.md), not public issues.

## Build and check

Requires macOS 13+, Swift 5.9+, and Xcode 15+ or compatible Command Line Tools.

```sh
git clone https://github.com/wangleijie5859/ShiTie.git
cd ShiTie
./scripts/test.sh
./scripts/build-app.sh
open "dist/拾贴.app"
```

`./scripts/build-app.sh debug` enables the appearance preview menu for manual checks. The test entry point is `scripts/test.sh`, rather than `swift test`: this project uses dependency-free executable checks that also work with Command Line Tools.

Tests create temporary databases and independent named pasteboards. The macOS pasteboard service must be reachable. If a sandbox blocks the integration checks, run them in a normal local terminal.

## Pull requests

- Keep each PR focused on one problem. Explain the user-visible change and how you checked it.
- Follow the existing Swift style. Prefer system frameworks and avoid new dependencies unless there is a concrete need.
- Add a focused check for changed storage, migration, clipboard, or editing behavior.
- For UI changes, check light/dark appearance and include screenshots with sample data when useful.
- Preserve user data, exact copied text, and error reporting. Never log clipboard contents or silently replace a failed database.
- Update the relevant README or guide when behavior changes. Never commit build outputs, credentials, or personal history.

By submitting a contribution, you agree that it may be distributed under this project's [MIT License](LICENSE). Be respectful and specific in discussions.
