# Simulator Server C++

This is a C++ implementation of the Pricing Simulator Server, designed for high-performance data generation and direct streaming to Google Cloud BigQuery.

## Features

- **High-Performance Simulation**: Core simulation loop implemented in C++ using `std::thread` and `std::chrono`.
- **BigQuery Streaming**: Implements the pattern for streaming data directly to BigQuery using the modern Storage Write API.
- **REST API**: Provides endpoints for status, configuration, and control (Start/Stop) using the Crow framework.
- **JSON Support**: Uses `nlohmann/json` for seamless configuration and message handling.

## Project Structure

- `src/main.cpp`: Entry point and REST server.
- `src/simulator.cpp/hpp`: Core simulation logic.
- `src/bigquery_client.cpp/hpp`: BigQuery Storage Write API client.
- `src/types.hpp`: Shared data structures.
- `src/pricing_message.proto`: Protobuf definition for BigQuery Storage Write API compatibility.

## Dependencies

- [Google Cloud CPP](https://github.com/googleapis/google-cloud-cpp): For BigQuery Storage Write API.
- [Crow](https://github.com/CrowCpp/Crow): For the REST API.
- [nlohmann/json](https://github.com/nlohmann/json): For JSON processing.

## Building

1. Ensure you have `cmake` and a modern C++ compiler (C++17 or later) installed.
2. Install dependencies (e.g., via `vcpkg` or the provided `FetchContent` in `CMakeLists.txt`).
3. Run:
   ```bash
   mkdir build && cd build
   cmake ..
   make
   ```

## Configuration

Copy `config.json` from the root directory to your build folder. The server expects this file for initial symbols, project ID, and simulation parameters.

## BigQuery Setup

The server expects a BigQuery table with the schema defined in `model/pricing-message-bq-schema.json`. Ensure the service account running the server has `BigQuery Data Editor` and `BigQuery Read Session User` roles.
