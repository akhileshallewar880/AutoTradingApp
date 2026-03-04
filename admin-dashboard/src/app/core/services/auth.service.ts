import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { BehaviorSubject, Observable } from 'rxjs';
import { tap } from 'rxjs/operators';

export interface LoginRequest {
  username: string;
  password: string;
}

export interface LoginResponse {
  access_token: string;
  token_type: string;
  expires_in: number;
}

@Injectable({
  providedIn: 'root'
})
export class AuthService {
  private apiUrl = 'http://localhost:8000/api/v1/admin';
  private tokenSubject = new BehaviorSubject<string | null>(this.getStoredToken());
  public isAuthenticated$ = new BehaviorSubject<boolean>(!!this.getStoredToken());

  constructor(
    private http: HttpClient,
    private router: Router
  ) {}

  login(username: string, password: string): Observable<LoginResponse> {
    return this.http.post<LoginResponse>(`${this.apiUrl}/auth/login`, {
      username,
      password
    }).pipe(
      tap(response => {
        this.storeToken(response.access_token);
        this.tokenSubject.next(response.access_token);
        this.isAuthenticated$.next(true);
      })
    );
  }

  logout(): void {
    this.clearToken();
    this.tokenSubject.next(null);
    this.isAuthenticated$.next(false);
    this.router.navigate(['/login']);
  }

  getToken(): string | null {
    return this.tokenSubject.value;
  }

  private storeToken(token: string): void {
    localStorage.setItem('admin_token', token);
  }

  private getStoredToken(): string | null {
    return localStorage.getItem('admin_token');
  }

  private clearToken(): void {
    localStorage.removeItem('admin_token');
  }

  isLoggedIn(): boolean {
    return !!this.getToken();
  }
}
