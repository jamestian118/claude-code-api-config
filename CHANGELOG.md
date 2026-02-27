# CHANGELOG

All notable changes to this project will be documented in this file.

## 0.1.0 - 2026-02-27

### Added
- `capi version` command and baseline regression tests.
- Health-check model configurability (`test_model`) in API entries.

### Changed
- Codex health check routes by `wire_api` (`responses` vs `chat`).
- Unified write path via `_capi_write` with safer temp-file handling.
- Documentation updates: English config example and parameterized policy-stack path guidance.
