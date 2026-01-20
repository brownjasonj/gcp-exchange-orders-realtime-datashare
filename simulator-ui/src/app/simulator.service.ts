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
  private sockets: Socket[] = [];
  private apiUrls: string[] = [];

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

    this.apiUrls.forEach((url, index) => {
      const socket = io(url, {
        transports: ['websocket', 'polling']
      });
      this.sockets.push(socket);
      this.setupSocketListeners(socket, index);
    });
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
      Object.keys(prices).forEach(key => {
        if (!merged[key]) {
             merged[key] = {}; // Initialize if new
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
