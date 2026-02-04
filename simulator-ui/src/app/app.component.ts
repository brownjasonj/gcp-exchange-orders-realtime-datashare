import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { SimulatorService, Config, PricingMessage } from './simulator.service';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.css']
})
export class AppComponent implements OnInit {
  status: any = null;
  prices: { key: string; bid?: number; ask?: number }[] = [];
  messages: PricingMessage[] = [];
  burstProgress: {
    shardIndex: number,
    generatingPercent: number,
    generatingCount: number,
    publishingPercent: number,
    publishingCount: number,
    phase: string,
    percentComplete: number
  }[] = [];
  minimizedBurstLog = false;

  configJsonString: string = '';
  configError: string | null = null;
  fatalError: string | null = null;



  constructor(private simService: SimulatorService) {
    const env = (window as any).ENV || {};
    const apiUrls = env.API_URLS || (env.API_URL ? [env.API_URL] : []);
    const projectId = env.PROJECT_ID;

    if (apiUrls.length === 0 || !projectId) {
      this.fatalError = 'Missing Configuration: API_URLS and PROJECT_ID must be defined in environment.';
      console.error(this.fatalError);
    } else {
      this.simService.initialize(apiUrls, projectId);
    }
  }

  ngOnInit() {
    if (this.fatalError) return;



    this.simService.status$.subscribe(s => {
      this.status = s;
      if (s && s.config) {
        // Only update text area if not focused? Or just on initial load?
        // For simplicity, we only update if we haven't touched it, or if it's null
        if (!this.configJsonString) {
          this.configJsonString = JSON.stringify(s.config, null, 2);
        }
      }
    });

    this.simService.prices$.subscribe(p => {
      // transform map to array for display
      this.prices = Object.entries(p).map(([k, v]) => ({ key: k, bid: v.bid, ask: v.ask }));
    });

    this.simService.priceUpdate$.subscribe(u => {
      if (u) {
        this.triggerFlash(u.key, u.field);
      }
    });

    this.simService.messages$.subscribe(m => {
      this.messages = m;
    });

    this.simService.burstProgress$.subscribe(p => {
      this.burstProgress = Array.from(p.entries()).map(([index, progress]) => ({
        shardIndex: index,
        ...progress
      })).sort((a, b) => a.shardIndex - b.shardIndex);
    });

    // Also fetch config explicitly
    this.simService.getConfig().subscribe(c => {
      this.configJsonString = JSON.stringify(c, null, 2);
    });
  }



  flashStates: Record<string, { bid: boolean, ask: boolean }> = {};

  triggerFlash(key: string, field: 'bid' | 'ask') {
    if (!this.flashStates[key]) {
      this.flashStates[key] = { bid: false, ask: false };
    }
    this.flashStates[key][field] = true;
    setTimeout(() => {
      this.flashStates[key][field] = false;
    }, 200); // 200ms flash
  }

  isFlashing(key: string, field: 'bid' | 'ask'): boolean {
    return this.flashStates[key]?.[field] || false;
  }

  get isRunning(): boolean {
    return this.status?.isRunning || false;
  }

  get isBursting(): boolean {
    return this.burstProgress.some(p => p.percentComplete < 100);
  }

  get totalBurstGeneratedCount(): number {
    return this.burstProgress.reduce((sum, p) => sum + p.generatingCount, 0);
  }

  get totalBurstPublishedCount(): number {
    return this.burstProgress.reduce((sum, p) => sum + p.publishingCount, 0);
  }

  get averageBurstPercent(): number {
    if (this.burstProgress.length === 0) return 0;
    return Math.round(this.burstProgress.reduce((sum, p) => sum + p.percentComplete, 0) / this.burstProgress.length);
  }

  toggleSimulation() {
    if (this.isRunning) {
      this.simService.stop().subscribe();
    } else {
      this.simService.start().subscribe();
    }
  }

  saveConfig() {
    try {
      this.configError = null;
      const config = JSON.parse(this.configJsonString);
      this.simService.updateConfig(config).subscribe({
        next: () => alert('Configuration Saved & Simulation Reset'),
        error: (err) => alert('Failed to save: ' + err.message)
      });
    } catch (e) {
      this.configError = (e as Error).message;
    }
  }

  toggleBurstLog() {
    this.minimizedBurstLog = !this.minimizedBurstLog;
  }
}
