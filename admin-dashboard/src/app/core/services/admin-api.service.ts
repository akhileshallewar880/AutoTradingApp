import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { AuthService } from './auth.service';

export interface AdminSummary {
  total_users: number;
  active_today: number;
  total_tokens_30d: number;
  total_tokens_all_time: number;
  estimated_cost_30d: number;
  estimated_cost_all_time: number;
  users_in_profit: number;
  total_profit: number;
  total_loss: number;
  trades_today: number;
  win_rate: number;
  timestamp: string;
}

export interface UserMetric {
  user_id: number;
  email: string;
  full_name: string;
  created_at: string;
  analyses_count: number;
  tokens_used: number;
  estimated_cost: number;
}

export interface TokenMetric {
  date: string;
  total_tokens: number;
  total_cost: number;
  users_count: number;
}

@Injectable({
  providedIn: 'root'
})
export class AdminApiService {
  private apiUrl = 'http://localhost:8000/api/v1/admin';

  constructor(
    private http: HttpClient,
    private authService: AuthService
  ) {}

  private getTokenParam(): string {
    const token = this.authService.getToken();
    return token ? `?token=${token}` : '';
  }

  getSummary(): Observable<AdminSummary> {
    return this.http.get<AdminSummary>(
      `${this.apiUrl}/metrics/summary${this.getTokenParam()}`
    );
  }

  getUserMetrics(limit: number = 50): Observable<UserMetric[]> {
    return this.http.get<UserMetric[]>(
      `${this.apiUrl}/metrics/users?limit=${limit}&token=${this.authService.getToken()}`
    );
  }

  getTokenMetrics(days: number = 30): Observable<TokenMetric[]> {
    return this.http.get<TokenMetric[]>(
      `${this.apiUrl}/metrics/tokens?days=${days}&token=${this.authService.getToken()}`
    );
  }

  subscribeToEvents(): Observable<SSEEvent> {
    return new Observable(observer => {
      const token = this.authService.getToken();
      const eventSource = new EventSource(
        `${this.apiUrl}/events?token=${token}`
      );

      eventSource.onmessage = (event) => {
        observer.next(JSON.parse(event.data));
      };

      eventSource.onerror = (error) => {
        observer.error(error);
        eventSource.close();
      };

      return () => {
        eventSource.close();
      };
    });
  }
}

export interface SSEEvent {
  timestamp: string;
  totalUsers: number;
  activeToday: number;
  tokens30d: number;
  cost30d: number;
  tradesToday: number;
  totalProfit: number;
  totalLoss: number;
}
