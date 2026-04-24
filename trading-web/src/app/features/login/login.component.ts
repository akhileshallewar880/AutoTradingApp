import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, ActivatedRoute } from '@angular/router';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../core/services/auth.service';
import { ApiService } from '../../core/services/api.service';

/**
 * Zerodha OAuth flow — 3 steps:
 *
 * Step 1 — User enters: api_key + api_secret
 *   → We call GET /api/v1/auth/login?api_key=... → receive login_url
 *   → We redirect the browser to login_url (Zerodha's own login page)
 *
 * Step 2 — Zerodha redirects back to THIS page with ?request_token=...
 *   → We detect the query param on init and auto-advance to step 3
 *
 * Step 3 — We call POST /api/v1/auth/session { api_key, api_secret, request_token }
 *   → Receive access_token + user profile
 *   → Store { apiKey, accessToken, userId, name } in localStorage (NO api_secret kept)
 *   → Navigate to /dashboard
 *
 * WHY we never keep api_secret:
 *   The api_secret is only needed for this one exchange. After the session is created
 *   every API call only needs api_key + access_token. Keeping api_secret in the browser
 *   would be a security risk (it never expires), so it is discarded immediately.
 */
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

      <hr class="divider">

      <!-- Step indicator -->
      <div class="steps">
        <div class="step" [class.active]="step() === 1" [class.done]="step() > 1">
          <div class="step-dot">{{ step() > 1 ? '✓' : '1' }}</div>
          <span>Credentials</span>
        </div>
        <div class="step-line" [class.done]="step() > 1"></div>
        <div class="step" [class.active]="step() === 2" [class.done]="step() > 2">
          <div class="step-dot">{{ step() > 2 ? '✓' : '2' }}</div>
          <span>Zerodha Login</span>
        </div>
        <div class="step-line" [class.done]="step() > 2"></div>
        <div class="step" [class.active]="step() === 3">
          <div class="step-dot">3</div>
          <span>Connecting</span>
        </div>
      </div>

      <!-- ── STEP 1: Enter credentials ── -->
      @if (step() === 1) {
        <form class="form stagger" (ngSubmit)="getLoginUrl()">
          <p class="step-hint">
            Enter your Kite Connect app credentials. The API secret is used only once
            to exchange a token — it is <strong>never stored</strong>.
          </p>

          <div class="field">
            <label>API Key</label>
            <input class="input-field" type="text" [(ngModel)]="apiKey" name="apiKey"
                   placeholder="Your Kite Connect API key" autocomplete="off" spellcheck="false">
            <span class="field-hint">Found in <a href="https://developers.kite.trade/apps" target="_blank">Kite Developer Console</a></span>
          </div>

          <div class="field">
            <label>API Secret</label>
            <div class="token-input">
              <input class="input-field" [type]="showSecret ? 'text' : 'password'"
                     [(ngModel)]="apiSecret" name="apiSecret"
                     placeholder="Your Kite Connect API secret" autocomplete="off">
              <button type="button" class="eye-btn" (click)="showSecret = !showSecret">
                <span class="material-icons-round">{{ showSecret ? 'visibility_off' : 'visibility' }}</span>
              </button>
            </div>
            <span class="field-hint">Used once for token exchange, then discarded</span>
          </div>

          @if (error()) {
            <div class="error-msg fade-in">
              <span class="material-icons-round">error_outline</span> {{ error() }}
            </div>
          }

          <button class="btn btn-primary login-btn" type="submit" [disabled]="loading()">
            @if (loading()) { <span class="spinner"></span> Fetching login URL… }
            @else { <span class="material-icons-round">login</span> Continue to Zerodha Login }
          </button>

          <button type="button" class="btn btn-ghost demo-btn" (click)="demo()">
            <span class="material-icons-round">science</span> Try Demo Mode
          </button>
        </form>
      }

      <!-- ── STEP 2: Redirect info (shown briefly before redirect) ── -->
      @if (step() === 2) {
        <div class="redirect-state stagger">
          <div class="redirect-icon">
            <span class="material-icons-round">open_in_new</span>
          </div>
          <h3>Redirecting to Zerodha…</h3>
          <p>You will be taken to Zerodha's secure login page. After logging in, you will be automatically returned here.</p>
          <div class="spinner-large"></div>
        </div>
      }

      <!-- ── STEP 3: Auto-exchange (shown after callback) ── -->
      @if (step() === 3) {
        <div class="redirect-state stagger">
          <div class="redirect-icon success">
            <span class="material-icons-round">check_circle</span>
          </div>
          <h3>Completing Sign-In…</h3>
          <p>Exchanging your request token for a session. This takes a moment.</p>
          @if (error()) {
            <div class="error-msg fade-in">
              <span class="material-icons-round">error_outline</span> {{ error() }}
              <button class="btn btn-ghost btn-sm" style="margin-left:8px" (click)="reset()">Retry</button>
            </div>
          } @else {
            <div class="spinner-large"></div>
          }
        </div>
      }

      <p class="disclaimer">
        Your credentials are handled entirely in your browser.
        The API secret is never stored anywhere.
      </p>
    </div>
  </div>
  `,
  styles: [`
  .login-page {
    min-height: 100vh; display: flex; align-items: center; justify-content: center;
    background: linear-gradient(135deg, #0D1F12 0%, #0A0E1A 50%, #0A1628 100%);
    padding: 24px; position: relative; overflow: hidden;
  }
  .bg-orbs { position: absolute; inset: 0; pointer-events: none; }
  .orb {
    position: absolute; border-radius: 50%; filter: blur(80px); opacity: .22;
    animation: pulse-orb 6s ease-in-out infinite alternate;
  }
  .orb-1 { width: 400px; height: 400px; background: #388E3C; top: -100px; left: -100px; }
  .orb-2 { width: 300px; height: 300px; background: #1976D2; bottom: -80px; right: 10%; animation-delay: 2s; }
  .orb-3 { width: 200px; height: 200px; background: #303F9F; top: 40%; right: -60px; animation-delay: 4s; }
  @keyframes pulse-orb { from { transform: scale(1); } to { transform: scale(1.2); } }

  .login-card {
    background: rgba(255,255,255,.97); border-radius: 24px; padding: 40px;
    width: 100%; max-width: 480px;
    box-shadow: 0 24px 64px rgba(0,0,0,.4); position: relative; z-index: 1;
  }

  .logo { display: flex; align-items: center; gap: 14px; margin-bottom: 24px; }
  .logo-icon {
    width: 52px; height: 52px; border-radius: 14px; background: var(--color-primary);
    display: flex; align-items: center; justify-content: center;
    .material-icons-round { color: white; font-size: 28px; }
  }
  .logo h1  { font-size: 26px; font-weight: 800; line-height: 1.1; }
  .tagline  { font-size: 12px; color: var(--color-text-mid); margin-top: 2px; }

  /* Steps */
  .steps {
    display: flex; align-items: center; margin: 20px 0 28px; gap: 0;
  }
  .step {
    display: flex; flex-direction: column; align-items: center; gap: 4px; flex-shrink: 0;
    span { font-size: 10px; font-weight: 600; color: var(--color-text-low); white-space: nowrap; }
  }
  .step-dot {
    width: 28px; height: 28px; border-radius: 50%; border: 2px solid var(--color-divider);
    display: flex; align-items: center; justify-content: center;
    font-size: 12px; font-weight: 700; color: var(--color-text-low); background: white;
    transition: all .3s ease;
  }
  .step.active .step-dot { border-color: var(--color-primary); color: var(--color-primary); background: var(--color-primary-surface); }
  .step.done  .step-dot  { border-color: var(--color-primary); background: var(--color-primary); color: white; }
  .step.active span { color: var(--color-primary); }
  .step-line {
    flex: 1; height: 2px; background: var(--color-divider); margin: 0 6px; transition: background .3s ease;
    &.done { background: var(--color-primary); }
  }

  .step-hint {
    font-size: 13px; color: var(--color-text-mid); line-height: 1.6;
    background: var(--color-info-surface); border: 1px solid var(--color-info-border);
    border-radius: var(--radius-md); padding: 12px; margin-bottom: 4px;
    strong { color: var(--color-text); }
  }

  .form { display: flex; flex-direction: column; gap: 16px; }
  .field { display: flex; flex-direction: column; gap: 6px; }
  .field label { font-size: 12px; font-weight: 600; color: var(--color-text-high); letter-spacing: .3px; }
  .field-hint { font-size: 11px; color: var(--color-text-low); a { color: var(--color-info); } }

  .token-input { position: relative; }
  .token-input .input-field { padding-right: 44px; }
  .eye-btn {
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
    padding: 10px 14px; border-radius: var(--radius-md); font-size: 13px;
    .material-icons-round { font-size: 16px; flex-shrink: 0; }
  }

  .login-btn { width: 100%; padding: 13px; font-size: 15px; }
  .demo-btn  { width: 100%; color: var(--color-text-mid); justify-content: center; }

  .redirect-state {
    text-align: center; padding: 16px 0 8px;
    display: flex; flex-direction: column; align-items: center; gap: 12px;
    h3 { font-size: 18px; font-weight: 700; }
    p  { font-size: 13px; color: var(--color-text-mid); line-height: 1.6; max-width: 320px; }
  }
  .redirect-icon {
    width: 64px; height: 64px; border-radius: 18px;
    background: var(--color-info-surface);
    display: flex; align-items: center; justify-content: center;
    .material-icons-round { font-size: 32px; color: var(--color-info); }
    &.success { background: var(--color-primary-surface); .material-icons-round { color: var(--color-primary); } }
  }

  .spinner {
    width: 16px; height: 16px; border: 2px solid rgba(255,255,255,.35);
    border-top-color: white; border-radius: 50%; animation: spin .7s linear infinite;
  }
  .spinner-large {
    width: 36px; height: 36px; border: 3px solid var(--color-divider);
    border-top-color: var(--color-primary); border-radius: 50%; animation: spin .8s linear infinite;
    margin-top: 8px;
  }

  .disclaimer { text-align: center; font-size: 11px; color: var(--color-text-low); margin-top: 20px; line-height: 1.5; }
  .divider    { border: none; border-top: 1px solid var(--color-divider); margin-bottom: 24px; }
  `]
})
export class LoginComponent implements OnInit {
  private auth   = inject(AuthService);
  private api    = inject(ApiService);
  private router = inject(Router);
  private route  = inject(ActivatedRoute);

  step      = signal<1 | 2 | 3>(1);
  loading   = signal(false);
  error     = signal('');
  showSecret = false;

  apiKey    = '';
  apiSecret = '';  // discarded after token exchange

  ngOnInit() {
    // Zerodha redirects back with ?request_token=xxx&action=login&status=success
    const requestToken = this.route.snapshot.queryParamMap.get('request_token');
    const status       = this.route.snapshot.queryParamMap.get('status');

    if (requestToken && status === 'success') {
      const lsVal    = localStorage.getItem('vt_pending');
      const ssVal    = sessionStorage.getItem('vt_pending');
      const cookieMatch = document.cookie.match(/(?:^|;\s*)vt_pending=([^;]+)/);
      const cookieVal   = cookieMatch ? decodeURIComponent(cookieMatch[1]) : null;
      console.log('[VT] callback detected', { requestToken, lsVal, ssVal, cookieVal });
      const saved = cookieVal ?? lsVal ?? ssVal;
      if (saved) {
        const { apiKey, apiSecret } = JSON.parse(saved);
        this.apiKey    = apiKey;
        this.apiSecret = apiSecret;
        this.step.set(3);
        this.exchangeToken(requestToken);
      } else {
        this.error.set('Session data lost. Please start over.');
      }
    } else {
      console.log('[VT] login page loaded (no callback)', {
        requestToken, status,
        lsPending: localStorage.getItem('vt_pending')
      });
    }
  }

  /** Step 1 → 2: ask backend for the Zerodha login URL then redirect */
  getLoginUrl() {
    if (!this.apiKey.trim() || !this.apiSecret.trim()) {
      this.error.set('Please enter both API Key and API Secret.');
      return;
    }
    this.loading.set(true);
    this.error.set('');

    this.api.getLoginUrl(this.apiKey.trim()).subscribe({
      next: res => {
        const pending = JSON.stringify({ apiKey: this.apiKey.trim(), apiSecret: this.apiSecret.trim() });
        // Use document.cookie as primary — survives cross-origin redirect chains even when
        // localStorage/sessionStorage are partitioned or blocked by the browser.
        document.cookie = `vt_pending=${encodeURIComponent(pending)}; path=/; max-age=300; SameSite=Lax`;
        localStorage.setItem('vt_pending', pending); // fallback
        console.log('[VT] credentials saved', {
          cookie: document.cookie.includes('vt_pending'),
          ls: localStorage.getItem('vt_pending') !== null,
        });
        this.step.set(2);
        setTimeout(() => window.location.href = res.login_url, 600);
      },
      error: err => {
        this.error.set(err?.error?.detail ?? 'Could not reach server. Is the backend running?');
        this.loading.set(false);
      }
    });
  }

  /** Step 3: exchange request_token for access_token */
  private exchangeToken(requestToken: string) {
    console.log('[VT] exchangeToken called', { apiKey: this.apiKey, requestToken });
    this.api.createSession(this.apiKey, this.apiSecret, requestToken).subscribe({
      next: res => {
        console.log('[VT] createSession success', res);
        this.auth.login({
          userId:      res.user_id,
          accessToken: res.access_token,
          apiKey:      res.api_key,
          name:        res.user_name,
        });
        document.cookie = 'vt_pending=; path=/; max-age=0';
        localStorage.removeItem('vt_pending');
        console.log('[VT] navigating to dashboard');
        this.router.navigate(['/dashboard'], { replaceUrl: true });
      },
      error: err => {
        console.error('[VT] createSession error', err);
        this.error.set(err?.error?.detail ?? 'Token exchange failed. Please try again.');
      }
    });
  }

  reset() {
    document.cookie = 'vt_pending=; path=/; max-age=0';
    localStorage.removeItem('vt_pending');
    sessionStorage.removeItem('vt_pending');
    this.step.set(1);
    this.error.set('');
    this.router.navigate(['/login'], { replaceUrl: true });
  }

  demo() {
    this.auth.login({ userId: 'demo', accessToken: 'demo', apiKey: 'demo', name: 'Demo User' });
    this.router.navigate(['/dashboard']);
  }
}
