import { loadConfig } from './config-loader';
import { Simulator } from './simulator';
import path from 'path';

const CONFIG_PATH = process.env.CONFIG_PATH || './config.json';

async function main() {
  try {
    const configPath = path.isAbsolute(CONFIG_PATH) 
      ? CONFIG_PATH 
      : path.join(process.cwd(), CONFIG_PATH);
    
    const config = loadConfig(configPath);
    const simulator = new Simulator(config);

    await simulator.start(); // This sets up an interval, so the process keeps running
    
    // Handle graceful shutdown
    const signalHandler = (signal: string) => {
      console.log(`Received ${signal}. Stopping simulator...`);
      simulator.stop();
      process.exit(0);
    };

    process.on('SIGINT', () => signalHandler('SIGINT'));
    process.on('SIGTERM', () => signalHandler('SIGTERM'));

  } catch (error) {
    console.error('Fatal error:', error);
    process.exit(1);
  }
}

main();
