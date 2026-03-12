# Pricing Simulator & UI

A TypeScript Node.js application that simulates a trading exchange's pricing stream, publishes to Google Cloud Pub/Sub, and provides an Angular Dashboard for control and monitoring.

## Prerequisites

- Node.js (v18+ recommended)
- Google Cloud Platform (GCP) Project with Pub/Sub API enabled
- Application Default Credentials (ADC) configured.

## Installation

1. Install all dependencies (Backend & Frontend):
   ```bash
   npm run setup
   ```
   *Note: If you encounter 403 errors, try `npm run setup --registry=https://registry.npmjs.org/`*

## Configuration

Edit `config.json` or use the UI to modify parameters.

## Running the Application

### Option 1: Full Stack (Production-like)
Build the UI and run the server which serves both the API and the static UI files.

1. Build the UI:
   ```bash
   npm run build-ui
   ```
2. Start the Server:
   ```bash
   npm start
   ```
3. Open browser at `http://localhost:3000`

### Option 2: Development (Hot Reload)
Run backend and frontend separately.

1. Start Backend:
   ```bash
   npm start
   ```
2. Start Frontend (in a new terminal):
   ```bash
   cd ui
   ng serve
   ```
   *Note: The frontend is configured to proxy to port 3000 in development.*

3. Open browser at `http://localhost:4200`

## Features

- **Start/Stop Simulation**: Toggle the pricing generation.
- **Real-time Pricing**: View current prices for all symbols.
- **Live Message Log**: See the simulated Pub/Sub messages as they are published.
- **Configuration Editor**: Modify simulation parameters (periodicity, volatility, etc.) on the fly.
