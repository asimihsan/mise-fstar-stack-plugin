# mise-fstar-stack-plugin

A mise tool plugin that installs the F* toolchain stack (F* + KaRaMeL) with pinned compatible versions.

## Features

- Installs both F* and KaRaMeL as a single tool
- Stack versions pin compatible F*/KaRaMeL/OCaml versions together
- Per-install opam isolation (clean uninstalls)
- macOS Gatekeeper handling for unsigned binaries

## Installation

```bash
mise plugin install fstar-stack https://github.com/asimihsan/mise-fstar-stack-plugin
```

## Usage

```bash
# List available versions
mise ls-remote fstar-stack

# Install a specific stack version
mise install fstar-stack@2025.10.06-stack.1

# Use in a project (mise.toml)
[tools]
fstar-stack = "2025.10.06-stack.1"
```

## Prerequisites

On macOS:
```bash
brew install opam make pkg-config gmp
```

On Linux:
```bash
# Ubuntu/Debian
sudo apt-get install opam build-essential pkg-config libgmp-dev
```

## Environment Variables

The plugin sets:
- `FSTAR_HOME` - F* installation directory
- `KRML_HOME` - KaRaMeL installation directory (when available)
- `PATH` - Adds F* binary, Z3 solver, and KaRaMeL binary

Override variables:
- `MISE_FSTAR_STACK_KARAMEL_REPO` - Override KaRaMeL git repository
- `MISE_FSTAR_STACK_KARAMEL_COMMIT` - Override KaRaMeL git commit/tag

## Development Status

- [x] F* binary installation
- [ ] KaRaMeL build from source
- [ ] Full prerequisite checking
- [ ] Multiple stack versions

## License

Mozilla Public License 2.0
