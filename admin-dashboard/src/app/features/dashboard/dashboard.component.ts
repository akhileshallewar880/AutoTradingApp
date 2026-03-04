import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Subject } from 'rxjs';
import { takeUntil } from 'rxjs/operators';
import { AdminApiService, AdminSummary, TokenMetric, UserMetric, SSEEvent } from '../../core/services/admin-api.service';
import { AuthService } from '../../core/services/auth.service';
import { Router } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatCardModule } from '@angular/material/card';
import { MatIconModule } from '@angular/material/icon';
import { MatToolbarModule } from '@angular/material/toolbar';
import { MatMenuModule } from '@angular/material/menu';
import { NgChartsModule } from 'ng2-charts';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [
    CommonModule,
    MatButtonModule,
    MatCardModule,
    MatIconModule,
    MatToolbarModule,
    MatMenuModule,
    NgChartsModule
  ],
  templateUrl: './dashboard.component.html',
  styleUrls: ['./dashboard.component.scss']
})
export class DashboardComponent implements OnInit, OnDestroy {
  summary: AdminSummary | null = null;
  userMetrics: UserMetric[] = [];
  tokenMetrics: TokenMetric[] = [];
  liveData: SSEEvent | null = null;
  loading = true;
  error: string | null = null;

  private destroy$ = new Subject<void>();

  // Chart data
  tokenChartLabels: string[] = [];
  tokenChartData: any[] = [];
  userChartLabels: string[] = [];
  userChartData: any[] = [];

  constructor(
    private adminApi: AdminApiService,
    private authService: AuthService,
    private router: Router
  ) {}

  ngOnInit(): void {
    this.loadMetrics();
    this.subscribeToLiveUpdates();
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
  }

  private loadMetrics(): void {
    this.loading = true;
    this.error = null;

    this.adminApi.getSummary()
      .pipe(takeUntil(this.destroy$))
      .subscribe({
        next: (data) => {
          this.summary = data;
          this.loading = false;
        },
        error: (err) => {
          this.error = 'Failed to load metrics';
          this.loading = false;
          console.error('Error loading metrics:', err);
        }
      });

    this.adminApi.getUserMetrics()
      .pipe(takeUntil(this.destroy$))
      .subscribe({
        next: (data) => {
          this.userMetrics = data;
        },
        error: (err) => {
          console.error('Error loading user metrics:', err);
        }
      });

    this.adminApi.getTokenMetrics(30)
      .pipe(takeUntil(this.destroy$))
      .subscribe({
        next: (data) => {
          this.tokenMetrics = data;
          this.updateTokenChart();
        },
        error: (err) => {
          console.error('Error loading token metrics:', err);
        }
      });
  }

  private subscribeToLiveUpdates(): void {
    this.adminApi.subscribeToEvents()
      .pipe(takeUntil(this.destroy$))
      .subscribe({
        next: (event: SSEEvent) => {
          this.liveData = event;
          // Update summary with live data
          if (this.summary) {
            this.summary.total_users = event.totalUsers;
            this.summary.active_today = event.activeToday;
            this.summary.total_tokens_30d = event.tokens30d;
            this.summary.estimated_cost_30d = event.cost30d;
            this.summary.trades_today = event.tradesToday;
            this.summary.total_profit = event.totalProfit;
            this.summary.total_loss = event.totalLoss;
          }
        },
        error: (err) => {
          console.error('SSE connection error:', err);
        }
      });
  }

  private updateTokenChart(): void {
    if (this.tokenMetrics.length === 0) return;

    this.tokenChartLabels = this.tokenMetrics
      .slice()
      .reverse()
      .map(m => m.date.substring(5));

    this.tokenChartData = [{
      label: 'Tokens Used',
      data: this.tokenMetrics
        .slice()
        .reverse()
        .map(m => m.total_tokens),
      borderColor: '#6c63ff',
      backgroundColor: 'rgba(108, 99, 255, 0.1)',
      borderWidth: 2,
      fill: true,
      tension: 0.4,
      pointRadius: 4,
      pointBackgroundColor: '#6c63ff',
      pointBorderColor: '#fff',
      pointBorderWidth: 2
    }];
  }

  logout(): void {
    this.authService.logout();
  }

  refreshData(): void {
    this.loadMetrics();
  }

  formatNumber(num: number | undefined): string {
    if (!num) return '0';
    return num.toLocaleString();
  }

  formatCurrency(num: number | undefined): string {
    if (!num) return '$0.00';
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD'
    }).format(num);
  }
}
