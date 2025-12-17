# Repository Guidelines

## Project Structure & Module Organization

- `metadata.lua`: mise plugin metadata (name, version, min runtime).
- `hooks/`: hook entrypoints called by mise (`available.lua`, `pre_install.lua`, `post_install.lua`, `env_keys.lua`).
- `lib/`: shared Lua modules (keep hooks thin; put reusable logic here). Notable files:
  - `lib/versions.lua`: stack manifest and version pins (`YYYY.MM.DD-stack.N`).
  - `lib/prerequisites.lua`, `lib/platform.lua`, `lib/find_install.lua`: platform + install helpers.
- `mise.toml` and `mise-tasks/`: local dev tooling and runnable tasks.
- `test/`: end-to-end scripts, Dockerfiles, and a small F* proof (`test/Coincidence.fst`) used as a functional check.

## Build, Test, and Development Commands

Run tasks via mise:

- `mise install`: installs dev tools pinned in `mise.toml` (e.g., `stylua`, `shellcheck`, `hk`).
- `mise run format`: formats Lua sources with Stylua.
- `mise run lint`: runs `hk check --all` (Lua lint/format checks) and `shellcheck test/*.sh`.
- `mise run ci`: runs the same checks as CI (`lint` + `test-smoke`).
- `mise run verify`: verifies an already-installed stack (version + `test/Coincidence.fst`).
- `mise run test-smoke`: installs a stack, skips KaRaMeL (`MISE_FSTAR_STACK_SKIP_KARAMEL=1`), then runs `verify`.
- `mise run test`: installs a stack (KaRaMeL built by default), then runs `verify`.

Optional Docker smoke test:

- `./test/build.sh [--no-cache]`: builds test images for `linux/amd64` and `linux/arm64` (set `GH_TOKEN` if GitHub API rate limits bite).

## Coding Style & Naming Conventions

- Lua should remain compatible with the plugin runtime; `.luacheckrc` is configured for `lua51`.
- Format first, then lint: prefer `mise run format` + `mise run lint` over manual formatting.
- Naming patterns:
  - Stack versions: `YYYY.MM.DD-stack.N` (update `lib/versions.lua`).
  - Hook files: `hooks/<hook_name>.lua` and keep hook signatures intact.

## Testing Guidelines

- Prefer end-to-end verification over unit tests: `mise run test` should pass on your platform.
- If you change platform handling, run the closest platform script in `test/` (e.g., `test/test-macos-native.sh` on macOS).

## Commit & Pull Request Guidelines

- Commits use short, imperative subjects (e.g., “Fix Linux x86_64 SHA256 checksum”).
- PRs should include: what changed, affected platforms, and verification steps (`mise run lint`, `mise run test`).
- If you change versions/checksums, update `lib/versions.lua` and keep `README.md` examples consistent.
