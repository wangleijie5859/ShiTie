# Security policy / 安全政策

拾贴保存剪贴板内容。请使用虚构文字复现问题，不要公开你的历史数据库、密码、密钥或其他人的信息。

ShiTie stores clipboard history locally. Please use synthetic examples and never share your clipboard database, passwords, tokens, or other people's data.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/wangleijie5859/ShiTie/security/advisories/new) for security problems. Include the affected version, macOS version, reproduction steps with sample data, and expected impact. Please avoid public issues for undisclosed vulnerabilities.

Security fixes target the latest published version. This is a community-maintained project with no guaranteed response time.

## Current security boundaries

- History is stored in SQLite without additional encryption. Use macOS account protection and FileVault as appropriate.
- Known concealed, transient, and password-manager markers are filtered; unmarked secrets cannot be identified reliably.
- Pause recording before copying sensitive information. Application-level deletion is not a guarantee of forensic erasure from storage or backups.
- Initial release binaries are ad-hoc signed and are not Developer ID signed or notarized.

The [README](README.en.md#privacy-and-limits) and [detailed guide](docs/GUIDE.zh-CN.md) describe current behavior.
