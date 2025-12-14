FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install prerequisites (comprehensive for opam builds)
RUN apt-get update && apt-get install -y \
    # Core build tools
    curl git build-essential pkg-config unzip \
    # GMP library
    libgmp-dev \
    # OPAM and OCaml build deps
    opam m4 rsync \
    # SSL/TLS for downloads
    ca-certificates libssl-dev \
    # Sometimes needed by opam packages
    zlib1g-dev python3 \
    && rm -rf /var/lib/apt/lists/*

# Disable opam sandboxing in container (required)
RUN opam init --bare --no-setup --disable-sandboxing

# Install mise
RUN curl https://mise.jdx.dev/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# Install plugin from GitHub
ARG GH_TOKEN
ENV GH_TOKEN=${GH_TOKEN}
RUN mise plugin install fstar-stack https://github.com/asimihsan/mise-fstar-stack-plugin

# --- LAYER CACHING OPTIMIZATION ---
# Copy only mise config first to cache tool installation
WORKDIR /workspace/proven-pool
COPY mise.toml mise.lock* ./

# Install fstar-stack (builds KaRaMeL - expensive, cache this layer)
RUN mise install fstar-stack@2025.10.06-stack.1

# Verify tools work
RUN mise exec -- fstar.exe --version
RUN mise exec -- Karamel.exe --version || \
    mise exec -- $(mise where fstar-stack)/karamel/_build/default/src/Karamel.exe --version

# Install GNU make
RUN mise install make@latest

# --- Now copy the rest of the code ---
COPY . ./

# Run full pipeline
RUN mise run verify
RUN mise run extract
RUN mise run build
RUN mise run run

# Success message
RUN echo "=== ALL TESTS PASSED ==="
