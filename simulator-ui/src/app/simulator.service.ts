import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { io, Socket } from 'socket.io-client';
import { Observable, BehaviorSubject } from 'rxjs';

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
  private socket!: Socket;
  private apiUrl = '';

  public status$ = new BehaviorSubject<any>(null);
  public prices$ = new BehaviorSubject<Record<string, { bid?: number, offer?: number }>>({});
  public priceUpdate$ = new BehaviorSubject<{ key: string, field: 'bid' | 'offer' } | null>(null);
  public messages$ = new BehaviorSubject<PricingMessage[]>([]);

  private messageLog: PricingMessage[] = [];
  private readonly MAX_LOG_SIZE = 50;
  private projectId = '';

  constructor(private http: HttpClient) {
  }

  initialize(apiUrl: string, projectId: string) {
    this.apiUrl = apiUrl;
    this.projectId = projectId;
    console.log(`Initializing SimulatorService with API_URL: ${this.apiUrl}, PROJECT_ID: ${this.projectId}`);

    this.socket = io(this.apiUrl, {
      transports: ['websocket', 'polling']
    });

    this.setupSocketListeners();
  }

  private setupSocketListeners() {
    this.socket.on('connect', () => {
      console.log('Connected to Simulator Backend');
    });

    this.socket.on('status', (status) => {
      this.status$.next(status);
    });

    // TODO: 'prices' event from server still sends map of number, not bid/offer objects. 
    // We might need to adjust or ignore it for now if we rely on updates. 
    // Actually, on initial load, we might not have bid/offer distinction if server just sends "latest value". 
    // Let's assume for now we start empty or with just a "last price" but we want split. 
    // For MVP, if server sends simple map, we might just put it as both or neither?
    // Let's update 'prices' event handler too if server sends it. 
    // Server 'getPrices' returns Map<string, number>. This is "last trade price" effectively. 
    // We can treat it as 'last' or maybe just ignore it if we want strict bid/offer. 
    // But let's keep it simple: we won't show anything until first bid or offer update comes in, or we treat initial as "last".
    // Actually, user asked for "latest bid and offer". 
    this.socket.on('prices', (prices: Record<string, number>) => {
      // Convert simple number to { bid?: number, offer?: number } ?
      // No, we can't infer. Let's start with empty or preserve existing structure if we can.
      // But we are changing the type of prices$. 
      // Let's just initialize keys with empty objects.
      const newPrices: Record<string, { bid?: number, offer?: number }> = {};
      Object.keys(prices).forEach(key => {
        newPrices[key] = {}; // We don't know if the stored price was bid or offer.
      });
      this.prices$.next(newPrices);
    });

    this.socket.on('priceUpdate', (update: { symbol: string, currency: string, price: number, bidOffer: 'bid' | 'offer' }) => {
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

    this.socket.on('message', (msg: PricingMessage) => {
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
  getConfig(): Observable<Config> {
    return this.http.get<Config>(`${this.apiUrl}/api/config`);
  }

  updateConfig(config: Config): Observable<any> {
    return this.http.post(`${this.apiUrl}/api/config`, config);
  }

  start(): Observable<any> {
    return this.http.post(`${this.apiUrl}/api/start`, {});
  }

  stop(): Observable<any> {
    return this.http.post(`${this.apiUrl}/api/stop`, {});
  }
}
