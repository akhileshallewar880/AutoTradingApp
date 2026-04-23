import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../core/services/auth.service';
import { ApiService } from '../../core/services/api.service';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [FormsModule, CommonModule],
  template: `
  <div class="login-page">
    <div class="bg-orbs">
      <div class="orb orb-1"></div>
      <div class="orb orb-2"></div>
      <div class="orb orb-3"></div>
    </div>

    <div class="login-card scale-in">
      <!-- Logo -->
      <div class="logo">
        <div class="logo-icon">
          <span class="material-icons-round">trending_up</span>
        </div>
        <div>
          <h1>VanTrade</h1>
          <p class="tagline">AI-Powered Equity Intelligence</p>
        </div>
      </div>

      <div class="divider"></div>

      <!-- Form -->
      <form (ngSubmit)="login()" class="form stagger">
        <div class="field">
          <label>Zerodha API Key</label>
          <input class="input-field" type="text" [(ngModel)]="apiKey" name="apiKey"
                 placeholder="Your Zerodha API key" autocomplete="off">
        </div>

        <div class="field">
          <label>Access Token</label>
          <div class="token-input">
            <input class="input-field" [type]="showToken ? 'text' : 'password'"
                   [(ngModel)]="accessToken" name="accessToken"
                   placeholder="Today's access token" autocomplete="off">
            <button type="button" class="toggle-btn" (click)="showToken = !showToken">
              <span class="material-icons-round">{{ showToken ? 'visibility_off' : 'visibility' }}</span>
            </button>
          </div>
        </div>

        @if (error()) {
          <div class="error-msg fade-in">
            <span class="material-icons-round">error_outline</span>
            {{ error() }}
          </div>
        }

        <button class="btn btn-primary login-btn" type="submit" [disabled]="loading()">
          @if (loading()) {
            <span class="spinner"></span> Connecting…
          } @else {
            <span class="material-icons-round">login</span> Connect to Zerodha
          }
        </button>

        <!-- Demo mode -->
        <button type="button" class="btn btn-ghost demo-btn" (click)="demo()">
          <span class="material-icons-round">science</span> Try Demo Mode
        </button>
      </form>

      <p class="disclaimer">
        Your credentials stay in your browser — we never store tokens on any server.
      </p>
    </div>
  </div>
  `,
  styles: [`
  .login-page {
    min-height: 100vh;
    display: flex; align-items: center; justify-content: center;
    background: linear-gradient(135deg, #0D1F12 0%, #0A0E1A 50%, #0A1628 100%);
    padding: 24px; position: relative; overflow: hidden;
  }

  /* Ambient background orbs */
  .bg-orbs { position: absolute; inset: 0; pointer-events: none; }
  .orb {
    position: absolute; border-radius: 50%;
    filter: blur(80px); opacity: .25;
    animation: pulse-orb 6s ease-in-out infinite alternate;
  }
  .orb-1 { width: 400px; height: 400px; background: #388E3C; top: -100px; left: -100px; animation-delay: 0s; }
  .orb-2 { width: 300px; height: 300px; background: #1976D2; bottom: -80px; right: 10%; animation-delay: 2s; }
  .orb-3 { width: 200px; height: 200px; background: #303F9F; top: 40%; right: -60px; animation-delay: 4s; }

  @keyframes pulse-orb {
    from { transform: scale(1); }
    to   { transform: scale(1.2); }
  }

  .login-card {
    background: rgba(255,255,255,.97);
    border-radius: 24px;
    padding: 40px;
    width: 100%; max-width: 440px;
    box-shadow: 0 24px 64px rgba(0,0,0,.4);
    position: relative; z-index: 1;
  }

  .logo {
    display: flex; align-items: center; gap: 14px; margin-bottom: 28px;
  }
  .logo-icon {
    width: 52px; height: 52px; border-radius: 14px;
    background: var(--color-primary);
    display: flex; align-items: center; justify-content: center;
    .material-icons-round { color: white; font-size: 28px; }
  }
  .logo h1 { font-size: 26px; font-weight: 800; color: var(--color-text); line-height: 1.1; }
  .tagline  { font-size: 12px; color: var(--color-text-mid); margin-top: 2px; }

  .divider  { border: none; border-top: 1px solid var(--color-divider); margin-bottom: 28px; }

  .form { display: flex; flex-direction: column; gap: 16px; }

  .field label {
    display: block; font-size: 12px; font-weight: 600;
    color: var(--color-text-high); margin-bottom: 6px; letter-spacing: .3px;
  }

  .token-input { position: relative; }
  .token-input .input-field { padding-right: 44px; }
  .toggle-btn {
    position: absolute; right: 10px; top: 50%; transform: translateY(-50%);
    background: none; border: none; cursor: pointer; color: var(--color-text-mid);
    display: flex; align-items: center;
    .material-icons-round { font-size: 18px; }
    &:hover { color: var(--color-primary); }
  }

  .error-msg {
    display: flex; align-items: center; gap: 8px;
    background: var(--color-danger-surface); color: var(--color-danger);
    border: 1px solid var(--color-danger-border);
    padding: 10px 14px; border-radius: var(--radius-md);
    font-size: 13px; font-weight: 500;
    .material-icons-round { font-size: 16px; }
  }

  .login-btn { width: 100%; padding: 13px; font-size: 15px; margin-top: 4px; }

  .spinner {
    width: 16px; height: 16px; border: 2px solid rgba(255,255,255,.4);
    border-top-color: white; border-radius: 50%;
    animation: spin .7s linear infinite;
  }

  .demo-btn { width: 100%; color: var(--color-text-mid); justify-content: center; }

  .disclaimer {
    text-align: center; font-size: 11px; color: var(--color-text-low);
    margin-top: 20px; line-height: 1.5;
  }
  `]
})
export class LoginComponent {
  private auth = inject(AuthService);
  private api  = inject(ApiService);
  private router = inject(Router);

  apiKey = '';
  accessToken = '';
  showToken = false;
  loading = signal(false);
  error = signal('');

  login() {
    if (!this.apiKey.trim() || !this.accessToken.trim()) {
      this.error.set('Please enter both API Key and Access Token.');
      return;
    }
    this.loading.set(true);
    this.error.set('');

    this.api.loginZerodha(this.apiKey.trim(), this.accessToken.trim()).subscribe({
      next: res => {
        this.auth.login({
          userId: res.user_id,
          accessToken: this.accessToken.trim(),
          apiKey: this.apiKey.trim(),
          name: res.name,
        });
        this.router.navigate(['/dashboard']);
      },
      error: err => {
        this.error.set(err?.error?.detail ?? 'Connection failed. Check your credentials.');
        this.loading.set(false);
      }
    });
  }

  demo() {
    this.auth.login({ userId: 'demo', accessToken: 'demo', apiKey: 'demo', name: 'Demo User' });
    this.router.navigate(['/dashboard']);
  }
}
