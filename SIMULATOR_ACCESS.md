# Simulator Access Guide

## Why is direct access blocked?
The Simulator UI and Server are deployed as **Private** Cloud Run services because your Organization Policy blocks public access. This prevents the browser from connecting directly to the cloud URLs.

## How to Fix: Use Local Proxy

To bypass the restrictions, you must run authentication proxies for **both** the Server and the UI locally.

### 1. Start the Server Proxy (Terminal 1)
This tunnels traffic from `localhost:3000` to the remote private server.
```bash
gcloud run services proxy simulator-server --region=us-central1 --port=3000
```
*Keep this terminal open.*

### 2. Start the UI Proxy (Terminal 2)
This tunnels traffic from `localhost:8080` to the remote private UI.
```bash
gcloud run services proxy simulator-ui --region=us-central1 --port=8080
```
*Keep this terminal open.*

### 3. Access the Simulator
Open your browser to:
[http://localhost:8080](http://localhost:8080)

The UI will detect it is running on localhost and automatically connect to the Server at `http://localhost:3000`, bypassing CORS and Authentication errors.
