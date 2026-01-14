import { PubSub, Topic } from '@google-cloud/pubsub';
import { Config, PricingMessage } from './types';
import pino from 'pino';

const logger = pino({
  level: 'info',
  formatters: {
    level: (label) => {
      return { level: label.toUpperCase() };
    },
  },
  timestamp: pino.stdTimeFunctions.isoTime,
});

import { EventEmitter } from 'events';

export class Simulator extends EventEmitter {
  private config: Config;
  private pubSubClient: PubSub;
  private topic: Topic;
  private prices: Map<string, number>;
  private sequenceNumber: number;
  private pairs: { symbol: string; currency: string }[];
  private isRunning: boolean;
  private intervalId?: NodeJS.Timeout;

  constructor(config: Config) {
    super();
    this.config = config;
    this.pubSubClient = new PubSub({ projectId: config.gcpProjectId });
    this.topic = this.pubSubClient.topic(config.pubsubTopicName);
    this.prices = new Map();
    this.sequenceNumber = 0;
    this.pairs = [];
    this.isRunning = false;

    this.initialize();
  }

  private initialize() {
    // Cartesian product of symbols and currencies
    for (const symbol of this.config.symbols) {
      for (const currency of this.config.currencies) {
        const pairKey = this.getPairKey(symbol, currency);
        // Initial random value between 10 and 1000
        const initialValue = parseFloat((Math.random() * 990 + 10).toFixed(2));
        this.prices.set(pairKey, initialValue);
        this.pairs.push({ symbol, currency });
      }
    }
    logger.info({ msg: 'Simulator initialized', pairsCount: this.pairs.length });
  }

  private getPairKey(symbol: string, currency: string): string {
    return `${symbol}:${currency}`;
  }

  private getRandomElement<T>(array: T[]): T {
    return array[Math.floor(Math.random() * array.length)];
  }

  private getNextValue(currentValue: number): number {
    const variationPercentage = this.config.priceVariationPercentage;
    // Random float between -variationPercentage and +variationPercentage
    const changePercent = (Math.random() * 2 - 1) * variationPercentage;
    const factor = 1 + changePercent / 100;
    let newValue = currentValue * factor;
    // Ensure price doesn't go negative or too close to zero
    if (newValue < 0.01) newValue = 0.01;
    return parseFloat(newValue.toFixed(2)); // keeping 2 decimal places implies currency
  }

  public async start() {
    if (this.isRunning) return;
    this.isRunning = true;
    logger.info(`Starting simulation with periodicity ${this.config.periodicityMs}ms`);

    this.intervalId = setInterval(async () => {
      await this.tick();
    }, this.config.periodicityMs);
  }

  public stop() {
    this.isRunning = false;
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = undefined;
    }
    logger.info('Simulation stopped');
  }

  public getStatus() {
    return { isRunning: this.isRunning, config: this.config };
  }

  public getPrices() {
    // Convert Map to object for JSON serialization
    return Object.fromEntries(this.prices);
  }

  public updateConfig(newConfig: Config) {
    const wasRunning = this.isRunning;
    if (wasRunning) this.stop();
    this.config = newConfig;
    // Re-initialize pairs if needed, or just update params. 
    // unique pairs might change so we should re-init prices logic or keep existing?
    // User requirement: "App should initially create list...". 
    // If we update config with new symbols, we should probably re-init or merge.
    // For MVP transparency, let's re-initialize the simulation state fully or partially.
    // Let's just update the config reference and handle periodicity change on restart.
    // If symbols changed, we need to rebuild pairs.
    this.pairs = [];
    this.prices.clear();
    this.initialize();

    if (wasRunning) this.start();
  }

  private async tick() {
    // Select random pair
    const pair = this.getRandomElement(this.pairs);
    const key = this.getPairKey(pair.symbol, pair.currency);
    const currentValue = this.prices.get(key) || 100; // should exist

    const newValue = this.getNextValue(currentValue);
    this.prices.set(key, newValue);

    // Select random venue
    const venue = this.getRandomElement(this.config.venues);

    const message: PricingMessage = {
      symbol: pair.symbol,
      sequenceNumber: this.sequenceNumber++,
      price: newValue,
      currency: pair.currency,
      venue: venue,
      timestamp: new Date().toISOString(),
      bidOffer: Math.random() > 0.5 ? 'bid' : 'offer',
      quantity: Math.floor(Math.random() * 1000) + 1
    };

    // Emit message immediately to update UI
    this.emit('message', message);

    // Publish
    const dataBuffer = Buffer.from(JSON.stringify(message));
    try {
      const messageId = await this.topic.publishMessage({ data: dataBuffer });
      logger.info({
        msg: 'Published pricing message',
        messageId,
        payload: message
      });
    } catch (error) {
      logger.error({
        msg: 'Failed to publish message',
        error: (error as Error).message,
        payload: message
      });
    }
  }
}
