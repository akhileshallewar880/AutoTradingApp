import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { AuthService } from './auth.service';

const BASE = 'http://localhost:8000/api/v1';

@Injectable({ providedIn: 'root' })
export class ApiService {
  private http = inject(HttpClient);
  private auth = inject(AuthService);

  private get creds() {
    const u = this.auth.user();
    return { access_token: u?.accessToken ?? '', api_key: u?.apiKey ?? '' };
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  /** Step 1: Get the Zerodha login URL for the given api_key */
  getLoginUrl(apiKey: string): Observable<{ login_url: string }> {
    return this.http.get<{ login_url: string }>(`${BASE}/auth/login`, {
      params: new HttpParams({ fromObject: { api_key: apiKey } })
    });
  }

  /**
   * Step 2: Exchange request_token for access_token.
   * api_secret is sent once here; never stored after this call.
   */
  createSession(apiKey: string, apiSecret: string, requestToken: string): Observable<{
    access_token: string; api_key: string; user_id: string;
    user_name: string; email: string;
  }> {
    return this.http.post<any>(`${BASE}/auth/session`, {
      api_key: apiKey, api_secret: apiSecret, request_token: requestToken
    });
  }

  /** Validate that a stored access_token is still alive */
  validateToken(apiKey: string, accessToken: string): Observable<{ valid: boolean }> {
    return this.http.get<{ valid: boolean }>(`${BASE}/auth/validate-token`, {
      params: new HttpParams({ fromObject: { api_key: apiKey, access_token: accessToken } })
    });
  }

  // ── Dashboard ─────────────────────────────────────────────────────────────

  getDashboardSummary(): Observable<any> {
    const { access_token, api_key } = this.creds;
    return this.http.get(`${BASE}/dashboard/summary`, {
      params: new HttpParams({ fromObject: { access_token, api_key } })
    });
  }

  // ── Portfolio ─────────────────────────────────────────────────────────────

  getHoldings(): Observable<{ holdings: any[] }> {
    const { access_token, api_key } = this.creds;
    return this.http.get<{ holdings: any[] }>(`${BASE}/portfolio/holdings`, {
      params: new HttpParams({ fromObject: { access_token, api_key } })
    });
  }

  // ── Ticker ────────────────────────────────────────────────────────────────

  /** One-shot price snapshot for given instrument tokens */
  getSnapshot(tokens: string): Observable<{ snapshot: Record<string, any> }> {
    const { access_token, api_key } = this.creds;
    return this.http.get<{ snapshot: Record<string, any> }>(`${BASE}/ticker/snapshot`, {
      params: new HttpParams({ fromObject: { access_token, api_key, tokens } })
    });
  }

  // ── Analysis ──────────────────────────────────────────────────────────────

  runAnalysis(params: {
    num_stocks: number; risk_percent: number; hold_duration_days: number;
    sectors: string[]; capital_to_use: number;
  }): Observable<any> {
    const { access_token, api_key } = this.creds;
    const u = this.auth.user()!;
    return this.http.post<any>(`${BASE}/analysis/run`, {
      ...params, access_token, api_key,
      user_id: Number(u.userId) || 1,
      analysis_date: new Date().toISOString().split('T')[0],
    });
  }

  confirmAnalysis(analysisId: string, holdDurationDays: number): Observable<any> {
    const { access_token, api_key } = this.creds;
    return this.http.post(`${BASE}/analysis/${analysisId}/confirm`, {
      confirmed: true, access_token, api_key, hold_duration_days: holdDurationDays
    });
  }
}
