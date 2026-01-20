import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { io, Socket } from 'socket.io-client';
import { Observable, BehaviorSubject, forkJoin, of } from 'rxjs';
import { map } from 'rxjs/operators';

declare var process: any;


export interface Config {
  periodicityMs: number;
  priceVariationPercentage: number;
  gcpProjectId: string;
  pubsubTopicName: string;
  symbols: string[];
  currencies: string[];
  venues: string[];
}

export interface PricingMessage {
  symbol: string;
  sequenceNumber: number;
  price: number;
  currency: string;
  venue: string;

  timestamp: string;
  bidOffer: 'bid' | 'offer';
  quantity: number;
}

@Injectable({
  providedIn: 'root'
})
export class SimulatorService {
  private activeSockets: Map<number, Socket> = new Map();
  public apiUrls: string[] = [];

  public status$ = new BehaviorSubject<any>(null);
  public prices$ = new BehaviorSubject<Record<string, { bid?: number, offer?: number }>>({});
  public priceUpdate$ = new BehaviorSubject<{ key: string, field: 'bid' | 'offer' } | null>(null);
  public messages$ = new BehaviorSubject<PricingMessage[]>([]);

  private messageLog: PricingMessage[] = [];
  private readonly MAX_LOG_SIZE = 50;
  private projectId = '';

  constructor(private http: HttpClient) {
  }

  initialize(apiUrls: string[], projectId: string) {
    this.apiUrls = apiUrls;
    this.projectId = projectId;
    console.log(`Initializing SimulatorService with ${this.apiUrls.length} API_URLS, PROJECT_ID: ${this.projectId}`);

    // Connect to all shards by default
    this.apiUrls.forEach((_, index) => {
      this.connectShard(index);
    });
  }

  getShardCount(): number {
    return this.apiUrls.length;
  }

  isShardConnected(index: number): boolean {
    return this.activeSockets.has(index);
  }

  connectShard(index: number) {
    if (this.activeSockets.has(index)) return;
    if (index < 0 || index >= this.apiUrls.length) return;

    const url = this.apiUrls[index];
    console.log(`Connecting to Shard ${index} at ${url}`);

    const socket = io(url, {
      transports: ['websocket', 'polling']
    });
    this.activeSockets.set(index, socket);
    this.setupSocketListeners(socket, index);
  }

  disconnectShard(index: number) {
    const socket = this.activeSockets.get(index);
    if (socket) {
      console.log(`Disconnecting form Shard ${index}`);
      socket.disconnect();
      this.activeSockets.delete(index);

      // Clear data associated with this shard? 
      // For now, we keep the prices in the view until cleared or overwritten, 
      // but maybe we should clear to avoid confusion.
      // Ideally we'd remove keys belonging to this shard, but we don't track which key came from which shard easily.
      // Let's just leave it, assuming user is switching views.
    }
  }

  disconnectAll() {
    this.activeSockets.forEach(s => s.disconnect());
    this.activeSockets.clear();
    this.prices$.next({});
    this.messages$.next([]);
    this.messageLog = [];
  }

  private setupSocketListeners(socket: Socket, index: number) {
    socket.on('connect', () => {
      console.log(`Connected to Simulator Backend Shard ${index}`);
    });

    socket.on('status', (status) => {
      // Just update status from any shard. They should be effectively sync'd by UI actions.
      this.status$.next(status);
    });

    socket.on('prices', (prices: Record<string, number>) => {
      const current = this.prices$.value;
      const merged = { ...current };
      
      // Merge new keys. 
      // Assumption: Shards have distinct symbols, so collisions are rare or don't matter (last win).
      Object.entries(prices).forEach(([key, price]) => {
        if (!merged[key]) {
          merged[key] = { bid: price, offer: price }; // Initialize with base price
        } else {
          // Optional: Update existing if we want to sync baseline, but protecting existing bid/offer spread is probably better
          // changing this to only fill gaps
          if (merged[key].bid === undefined) merged[key].bid = price;
          if (merged[key].offer === undefined) merged[key].offer = price;
        }
      });
      this.prices$.next(merged);
    });

    socket.on('priceUpdate', (update: { symbol: string, currency: string, price: number, bidOffer: 'bid' | 'offer' }) => {
      const current = this.prices$.value;
      const key = `${update.symbol}:${update.currency}`;
      const entry = current[key] || {};

      const newEntry = { ...entry };
      if (update.bidOffer === 'bid') {
        newEntry.bid = update.price;
      } else {
        newEntry.offer = update.price;
      }

      this.prices$.next({ ...current, [key]: newEntry });
      this.priceUpdate$.next({ key, field: update.bidOffer });
    });

    socket.on('message', (msg: PricingMessage) => {
      this.addMessage(msg);
    });
  }

  private addMessage(msg: PricingMessage) {
    this.messageLog.unshift(msg);
    if (this.messageLog.length > this.MAX_LOG_SIZE) {
      this.messageLog.pop();
    }
    this.messages$.next([...this.messageLog]);
  }

  // API Methods
  
  // Get config from the first shard (assuming consistent config)
  getConfig(): Observable<Config> {
    if (this.apiUrls.length === 0) return of({} as Config);
    return this.http.get<Config>(`${this.apiUrls[0]}/api/config`);
  }

  updateConfig(config: Config): Observable<any[]> {
    const reqs = this.apiUrls.map(url => this.http.post(`${url}/api/config`, config));
    return forkJoin(reqs);
  }

  start(): Observable<any[]> {
    const reqs = this.apiUrls.map(url => this.http.post(`${url}/api/start`, {}));
    return forkJoin(reqs);
  }

  stop(): Observable<any[]> {
    const reqs = this.apiUrls.map(url => this.http.post(`${url}/api/stop`, {}));
    return forkJoin(reqs);
  }
}
