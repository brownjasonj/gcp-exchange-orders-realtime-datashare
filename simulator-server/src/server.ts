import express from 'express';
import http from 'http';
import { Server as SocketIOServer } from 'socket.io';
import cors from 'cors';
import path from 'path';
import fs from 'fs';
import { loadConfig } from './config-loader';
import { Simulator } from './simulator';
import { Config } from './types';

const PORT = parseInt(process.env.PORT || '3000', 10); // GCF usually defaults to 8080
const CONFIG_PATH = process.env.CONFIG_PATH || './config.json';
const DIST_PATH = path.join(__dirname, '../../simulator-ui/dist/ui/browser');

export const app = express();
// Note: We create a server for local/standalone usage. 
// When running in GCF via 'app' export, the framework creates its own server, 
// so Socket.IO attached to *this* server might not work in GCF unless we are in "custom" mode.
const server = http.createServer(app);

export const io = new SocketIOServer(server, {
  cors: {
    origin: ["http://localhost:8080", "http://localhost:4200"],
    methods: ["GET", "POST"],
    credentials: true
  }
});

app.use(cors({ origin: true, credentials: true }));
app.use(express.json());

// Load Config & Init Simulator
let configPath = path.isAbsolute(CONFIG_PATH)
  ? CONFIG_PATH
  : path.join(process.cwd(), CONFIG_PATH);

// Ensure config exists or use default
let config: Config;
try {
  // If file doesn't exist log warning
  if (!fs.existsSync(configPath)) {
    console.warn(`Config file not found at ${configPath}`);
    // Fallback or error? For now let's try to load it anyway or fail.
    // The simulator needs config to start.
  }
  config = loadConfig(configPath);
} catch (e) {
  console.error("Could not load config:", e);
  // We might not want to exit if imported as module in GCF test, but for app we need config.
  // For now, let's create a dummy config to prevent crash on import if file missing?
  // But strictly, we expect config.json to represent the deployed state.
  config = {
    periodicityMs: 1000,
    priceVariationPercentage: 1,
    gcpProjectId: process.env.PROJECT_ID || 'loading',
    pubsubTopicName: process.env.PUBSUB_TOPIC || 'pricing-topic',
    symbols: ['BTC', 'ETH'],
    currencies: ['USD'],
    venues: ['GCP']
  };
}

const simulator = new Simulator(config);

// Setup Socket.io events
io.on('connection', (socket) => {
  console.log('Client connected');
  socket.emit('status', simulator.getStatus());
  socket.emit('prices', simulator.getPrices());
  socket.on('disconnect', () => {
    console.log('Client disconnected');
  });
});

// Simulator Events
simulator.on('message', (message) => {
  io.emit('message', message);
  io.emit('priceUpdate', { symbol: message.symbol, currency: message.currency, price: message.price, bidOffer: message.bidOffer });
});

// API Routes
app.get('/api/config', (req, res) => {
  res.json(simulator.getStatus().config);
});

app.post('/api/config', (req, res) => {
  const newConfig = req.body as Config;
  try {
    simulator.updateConfig(newConfig);
    // Attempt to save to disk if possible (might be read-only in GCF)
    try {
      fs.writeFileSync(configPath, JSON.stringify(newConfig, null, 2));
    } catch (fsErr) {
      console.warn("Could not write config to disk (read-only filesystem?)", fsErr);
    }
    res.json({ success: true, config: newConfig });
    io.emit('status', simulator.getStatus());
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.post('/api/start', (req, res) => {
  simulator.start();
  res.json({ success: true });
  io.emit('status', simulator.getStatus());
});

app.post('/api/stop', (req, res) => {
  simulator.stop();
  res.json({ success: true });
  io.emit('status', simulator.getStatus());
});

app.get('/api/status', (req, res) => {
  res.json(simulator.getStatus());
});

app.get('/api/prices', (req, res) => {
  res.json(simulator.getPrices());
});

// Serve FE
if (fs.existsSync(DIST_PATH)) {
  app.use(express.static(DIST_PATH));
  app.get(/(.*)/, (req, res) => {
    if (req.path.startsWith('/api')) {
      return res.status(404).send('Not found');
    }
    res.sendFile(path.join(DIST_PATH, 'index.html'));
  });
} else {
  app.get('/', (req, res) => {
    res.send('Pricing Simulator API Running. UI not served.');
  });
}

// Graceful shutdown helpers
const shutdown = () => {
  console.log('Shutting down...');
  simulator.stop();
  server.close(() => {
    process.exit(0);
  });
};

// Only listen if run directly
if (require.main === module) {
  server.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
  });

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}
