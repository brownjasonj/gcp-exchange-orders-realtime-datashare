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
  bidAsk: 'bid' | 'ask';
  quantity: number;
}

@Injectable({
  providedIn: 'root'
})
export class SimulatorService {
  private activeSockets: Map<number, Socket> = new Map();
  public apiUrls: string[] = [];

  public status$ = new BehaviorSubject<any>(null);
  public prices$ = new BehaviorSubject<Record<string, { bid?: number, ask?: number }>>({});
  public priceUpdate$ = new BehaviorSubject<{ key: string, field: 'bid' | 'ask' } | null>(null);
  public messages$ = new BehaviorSubject<PricingMessage[]>([]);
  public burstProgress$ = new BehaviorSubject<Map<number, {
    generatingPercent: number,
    generatingCount: number,
    publishingPercent: number,
    publishingCount: number,
    phase: string,
    percentComplete: number // legacy for backward compatibility if needed in UI
  }>>(new Map());

  private messageLog: PricingMessage[] = [];
  private readonly MAX_LOG_SIZE = 50;
  private projectId = '';

  constructor(private http: HttpClient) {
  }

  initialize(apiUrls: string[], projectId: string) {
    this.apiUrls = apiUrls;
    this.projectId = projectId;
    console.log(`[DEBUG] Initializing SimulatorService with ${this.apiUrls.length} API_URLS, PROJECT_ID: ${this.projectId}`);
    console.log(`[DEBUG] API URLs:`, this.apiUrls);

    // Reset progress map
    this.burstProgress$.next(new Map());

    // Connect to all shards by default
    this.apiUrls.forEach((url, index) => {
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
    console.log(`[DEBUG] Attempting to connect to Shard ${index} at ${url}`);

    // Use a clean URL without trailing slash for Socket.IO if possible
    const cleanUrl = url.endsWith('/') ? url.slice(0, -1) : url;

    const socket = io(cleanUrl, {
      transports: ['websocket'],
      withCredentials: true,
      reconnectionAttempts: 5,
      timeout: 10000
    });

    this.activeSockets.set(index, socket);
    this.setupSocketListeners(socket, index);
  }

  disconnectShard(index: number) {
    const socket = this.activeSockets.get(index);
    if (socket) {
      console.log(`[DEBUG] Disconnecting from Shard ${index}`);
      socket.disconnect();
      this.activeSockets.delete(index);
    }
  }

  disconnectAll() {
    console.log('[DEBUG] Disconnecting all shards');
    this.activeSockets.forEach(s => s.disconnect());
    this.activeSockets.clear();
    this.prices$.next({});
    this.messages$.next([]);
    this.messageLog = [];
  }

  private setupSocketListeners(socket: Socket, index: number) {
    socket.on('connect', () => {
      console.log(`[DEBUG] [Shard ${index}] Connected to WebSocket`);
    });

    socket.on('connect_error', (err) => {
      console.error(`[DEBUG] [Shard ${index}] Connection Error:`, err.message, err);
    });

    socket.on('disconnect', (reason) => {
      console.warn(`[DEBUG] [Shard ${index}] Disconnected:`, reason);
    });

    socket.on('reconnect_attempt', (num) => {
      console.log(`[DEBUG] [Shard ${index}] Reconnect attempt ${num}`);
    });

    socket.on('status', (status) => {
      console.log(`[DEBUG] [Shard ${index}] Received status:`, status);
      // Just update status from any shard. They should be effectively sync'd by UI actions.
      this.status$.next(status);
    });

    socket.on('prices', (prices: Record<string, number>) => {
      console.log(`[DEBUG] [Shard ${index}] Received initial prices:`, Object.keys(prices).length, "symbols");
      const current = this.prices$.value;
      const merged = { ...current };

      Object.entries(prices).forEach(([key, price]) => {
        if (!merged[key]) {
          merged[key] = { bid: price, ask: price };
        } else {
          if (merged[key].bid === undefined) merged[key].bid = price;
          if (merged[key].ask === undefined) merged[key].ask = price;
        }
      });
      this.prices$.next(merged);
    });

    socket.on('priceUpdate', (update: { symbol: string, currency: string, price: number, bidAsk: 'bid' | 'ask' }) => {
      const current = this.prices$.value;
      const key = `${update.symbol}:${update.currency}`;
      const entry = current[key] || {};

      const newEntry = { ...entry };
      if (update.bidAsk === 'bid') {
        newEntry.bid = update.price;
      } else {
        newEntry.ask = update.price;
      }

      this.prices$.next({ ...current, [key]: newEntry });
      this.priceUpdate$.next({ key, field: update.bidAsk });
    });

    socket.on('message', (msg: PricingMessage) => {
      this.addMessage(msg);
    });

    socket.on('burstProgress', (progress: { percentComplete: number, messageCount: number, phase: string }) => {
      const current = this.burstProgress$.value;
      const existing = current.get(index) || {
        generatingPercent: 0,
        generatingCount: 0,
        publishingPercent: 0,
        publishingCount: 0,
        phase: 'generating',
        percentComplete: 0
      };

      const updated = {
        ...existing,
        phase: progress.phase,
        percentComplete: progress.percentComplete
      };

      if (progress.phase === 'generating') {
        updated.generatingCount = progress.messageCount;
        updated.generatingPercent = progress.percentComplete;
      } else if (progress.phase === 'publishing') {
        updated.publishingCount = progress.messageCount;
        updated.publishingPercent = progress.percentComplete;
      }

      current.set(index, updated);
      this.burstProgress$.next(new Map(current));
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

  getConfig(): Observable<Config> {
    if (this.apiUrls.length === 0) return of({} as Config);
    return this.http.get<Config>(`${this.apiUrls[0]}/api/config`, { withCredentials: true });
  }

  updateConfig(config: Config): Observable<any[]> {
    console.log('[DEBUG] Updating configuration on all shards');
    this.burstProgress$.next(new Map());
    const reqs = this.apiUrls.map(url => this.http.post(`${url}/api/config`, config, { withCredentials: true }));
    return forkJoin(reqs);
  }

  start(): Observable<any[]> {
    console.log('[DEBUG] Starting simulation on all shards');
    this.burstProgress$.next(new Map());
    const reqs = this.apiUrls.map(url => this.http.post(`${url}/api/start`, {}, { withCredentials: true }));
    return forkJoin(reqs).pipe(
      map(res => {
        const current = this.status$.value || { isRunning: false, config: {} };
        this.status$.next({ ...current, isRunning: true });
        return res;
      })
    );
  }

  stop(): Observable<any[]> {
    console.log('[DEBUG] Stopping simulation on all shards');
    const reqs = this.apiUrls.map(url => this.http.post(`${url}/api/stop`, {}, { withCredentials: true }));
    return forkJoin(reqs).pipe(
      map(res => {
        const current = this.status$.value || { isRunning: true, config: {} };
        this.status$.next({ ...current, isRunning: false });
        return res;
      })
    );
  }
}
