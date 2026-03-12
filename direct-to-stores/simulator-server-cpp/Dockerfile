ARG SDK_BASE
FROM ${SDK_BASE} AS builder

WORKDIR /app
COPY . .

# Use pre-installed SDK in /usr/local and install additional dependencies for Drogon
RUN apt-get update && apt-get install -y --no-install-recommends \
    libjsoncpp-dev \
    uuid-dev \
    zlib1g-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release .. && \
    make -j$(nproc)

# Final runtime image
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 \
    libcurl4 \
    libprotobuf32 \
    libgrpc++1.51 \
    libboost-system1.74.0 \
    libboost-date-time1.74.0 \
    libboost-thread1.74.0 \
    libjsoncpp25 \
    libuuid1 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /usr/local /usr/local
COPY --from=builder /app/build/simulator-server-cpp .
COPY --from=builder /app/config.json .

RUN ldconfig

EXPOSE 8080
CMD ["./simulator-server-cpp"]
