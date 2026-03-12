FROM rust:latest as builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y pkg-config libssl-dev protobuf-compiler && rm -rf /var/lib/apt/lists/*


# Copy manifest and lock file
COPY Cargo.toml Cargo.lock ./

# Create dummy main to cache dependencies
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release

# Copy actual source code
COPY src src
# Touch main.rs to force rebuild
RUN touch src/main.rs
RUN cargo build --release

# Runtime stage
FROM debian:bookworm

WORKDIR /app

# Install necessary runtime dependencies
RUN apt-get update && apt-get install -y ca-certificates libssl3 openssl && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/simulator-server-rust /app/simulator-server-rust
COPY config.json /app/config.json

# Environment variables
# Environment variables
ENV PORT=8080
ENV CONFIG_PATH=./config.json
ENV RUST_BACKTRACE=1

EXPOSE 8080

# Make sure the binary is executable
RUN chmod +x /app/simulator-server-rust

# Use shell form to allow debugging, but exec the final binary to receive signals
CMD ["/bin/bash", "-c", "echo 'Starting server...'; echo 'Checking libraries:'; ldd ./simulator-server-rust; echo 'Launching binary...'; exec ./simulator-server-rust"]

