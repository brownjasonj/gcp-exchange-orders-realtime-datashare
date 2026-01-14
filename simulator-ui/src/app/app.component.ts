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
  prices: { key: string; bid?: number; offer?: number }[] = [];
  messages: PricingMessage[] = [];

  configJsonString: string = '';
  configError: string | null = null;
  fatalError: string | null = null;

  constructor(private simService: SimulatorService) {
    const env = (window as any).ENV || {};
    const apiUrl = env.API_URL;
    const projectId = env.PROJECT_ID;

    if (!apiUrl || !projectId) {
      this.fatalError = 'Missing Configuration: API_URL and PROJECT_ID must be defined in environment.';
      console.error(this.fatalError);
    } else {
      this.simService.initialize(apiUrl, projectId);
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
      this.prices = Object.entries(p).map(([k, v]) => ({ key: k, bid: v.bid, offer: v.offer }));
    });

    this.simService.priceUpdate$.subscribe(u => {
      if (u) {
        this.triggerFlash(u.key, u.field);
      }
    });

    this.simService.messages$.subscribe(m => {
      this.messages = m;
    });

    // Also fetch config explicitly
    this.simService.getConfig().subscribe(c => {
      this.configJsonString = JSON.stringify(c, null, 2);
    });
  }

  flashStates: Record<string, { bid: boolean, offer: boolean }> = {};

  triggerFlash(key: string, field: 'bid' | 'offer') {
    if (!this.flashStates[key]) {
      this.flashStates[key] = { bid: false, offer: false };
    }
    this.flashStates[key][field] = true;
    setTimeout(() => {
      this.flashStates[key][field] = false;
    }, 200); // 200ms flash
  }

  isFlashing(key: string, field: 'bid' | 'offer'): boolean {
    return this.flashStates[key]?.[field] || false;
  }

  get isRunning(): boolean {
    return this.status?.isRunning || false;
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
}
