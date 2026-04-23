import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable, of, delay } from 'rxjs';
import { AuthService } from './auth.service';
import { DashboardData, AnalysisResult, IndexPrice } from '../models';

const BASE = 'http://localhost:8000/api/v1';

@Injectable({ providedIn: 'root' })
export class ApiService {
  private http = inject(HttpClient);
  private auth = inject(AuthService);

  private get creds() {
    const u = this.auth.user();
    return { access_token: u?.accessToken ?? '', api_key: u?.apiKey ?? '' };
  }

  getDashboard(): Observable<DashboardData> {
    const { access_token, api_key } = this.creds;
    return this.http.get<DashboardData>(`${BASE}/portfolio/dashboard`, {
      params: new HttpParams({ fromObject: { access_token, api_key } })
    });
  }

  getHoldings(): Observable<{ holdings: any[] }> {
    const { access_token, api_key } = this.creds;
    return this.http.get<{ holdings: any[] }>(`${BASE}/portfolio/holdings`, {
      params: new HttpParams({ fromObject: { access_token, api_key } })
    });
  }

  getIndexPrices(): Observable<{ snapshot: Record<string, any> }> {
    const { access_token, api_key } = this.creds;
    return this.http.get<{ snapshot: Record<string, any> }>(`${BASE}/ticker/snapshot`, {
      params: new HttpParams({ fromObject: { access_token, api_key, tokens: '256265,260105' } })
    });
  }

  runAnalysis(params: {
    num_stocks: number; risk_percent: number; hold_duration_days: number;
    sectors: string[]; capital_to_use: number;
  }): Observable<AnalysisResult> {
    const { access_token, api_key } = this.creds;
    const u = this.auth.user()!;
    return this.http.post<AnalysisResult>(`${BASE}/analysis/run`, {
      ...params, access_token, api_key,
      user_id: Number(u.userId),
      analysis_date: new Date().toISOString().split('T')[0],
    });
  }

  confirmAnalysis(analysisId: string): Observable<any> {
    const { access_token, api_key } = this.creds;
    return this.http.post(`${BASE}/analysis/${analysisId}/confirm`, {
      confirmed: true, access_token, api_key, hold_duration_days: 0
    });
  }

  loginZerodha(apiKey: string, accessToken: string): Observable<{ user_id: string; name: string }> {
    return this.http.post<{ user_id: string; name: string }>(`${BASE}/auth/login`, {
      api_key: apiKey, access_token: accessToken
    });
  }
}
