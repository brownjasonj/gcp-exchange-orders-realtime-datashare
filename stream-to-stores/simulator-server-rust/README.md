# Simulator Server (Rust)

This is a Rust implementation of the simulator server.

## Prerequisites
- Rust (latest stable)
- Google Cloud Credentials (if running with Pub/Sub)

## Running
```bash
cargo run
```

## Configuration
The server loads `config.json` from the current directory or `CONFIG_PATH` env var.
Defaults are provided if config is missing.

## Environment Variables
- `PORT`: Server port (default 3000)
- `CONFIG_PATH`: Path to config file
- `SHARD_INDEX`: Shard index (default 0)
- `TOTAL_SHARDS`: Total shards (default 1)
- `PROJECT_ID`: GCP Project ID (for PubSub)
- `PUBSUB_TOPIC`: PubSub topic name 

## API
- `GET /api/status`
- `GET /api/prices`
- `GET /api/config`
- `POST /api/config`
- `POST /api/start`
- `POST /api/stop`

## Architecture
- **Axum**: Web server
- **Socketioxide**: Socket.IO support
- **Tokio**: Async runtime
- **Google Cloud PubSub**: Realtime publishing
