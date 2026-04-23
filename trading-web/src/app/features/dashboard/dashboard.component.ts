import {
  Component, OnInit, OnDestroy, inject, signal, computed, ChangeDetectionStrategy
} from '@angular/core';
import { CommonModule, DecimalPipe, CurrencyPipe, PercentPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { interval, Subscription } from 'rxjs';
import { switchMap, startWith } from 'rxjs/operators';
import { AuthService } from '../../core/services/auth.service';
import { ApiService  } from '../../core/services/api.service';
import {
  Holding, Position, Gtt, StockAnalysis, AnalysisResult, DashboardData
} from '../../core/models';

/* ── Demo seed data ─────────────────────────────────────────────── */
const DEMO_HOLDINGS: Holding[] = [
  { tradingsymbol:'RELIANCE', company:'Reliance Industries', quantity:5, average_price:2840, last_price:2910,
    pnl:350, pnl_pct:2.46, day_change:42, day_change_pct:1.47, invested:14200, current_value:14550,
    stop_loss:2780, target:3050, max_profit:1050, max_loss:300, has_gtt:true, gtt_id:'g1' },
  { tradingsymbol:'TCS', company:'Tata Consultancy Services', quantity:2, average_price:3560, last_price:3490,
    pnl:-140, pnl_pct:-1.97, day_change:-28, day_change_pct:-0.79, invested:7120, current_value:6980,
    stop_loss:3400, target:3800, max_profit:480, max_loss:320, has_gtt:true, gtt_id:'g2' },
  { tradingsymbol:'HDFCBANK', company:'HDFC Bank', quantity:8, average_price:1640, last_price:1680,
    pnl:320, pnl_pct:2.44, day_change:18, day_change_pct:1.08, invested:13120, current_value:13440,
    stop_loss:0, target:0, max_profit:0, max_loss:0, has_gtt:false },
  { tradingsymbol:'INFY', company:'Infosys', quantity:10, average_price:1450, last_price:1430,
    pnl:-200, pnl_pct:-1.38, day_change:-12, day_change_pct:-0.83, invested:14500, current_value:14300,
    stop_loss:1380, target:1580, max_profit:1300, max_loss:700, has_gtt:true, gtt_id:'g3' },
];
const DEMO_POSITIONS: Position[] = [
  { tradingsymbol:'NIFTY24DEC25000CE', product:'MIS', quantity:50, average_price:142, last_price:168,
    pnl:1300, realised:0, unrealised:1300 },
  { tradingsymbol:'SBIN', product:'MIS', quantity:100, average_price:782, last_price:776,
    pnl:-600, realised:0, unrealised:-600 },
];
const DEMO_GTTS: Gtt[] = [
  { id:11111, tradingsymbol:'RELIANCE', type:'two-leg', status:'active', trigger_values:[2780,3050], quantity:5, last_price:2910 },
  { id:22222, tradingsymbol:'TCS', type:'two-leg', status:'active', trigger_values:[3400,3800], quantity:2, last_price:3490 },
  { id:33333, tradingsymbol:'INFY', type:'two-leg', status:'active', trigger_values:[1380,1580], quantity:10, last_price:1430 },
];
const DEMO_STOCKS: StockAnalysis[] = [
  { stock_symbol:'WIPRO', company_name:'Wipro Ltd', action:'BUY', entry_price:540, stop_loss:522,
    target_price:578, quantity:18, risk_amount:324, potential_profit:684, potential_loss:324,
    risk_reward_ratio:2.1, confidence_score:.84,
    ai_reasoning:'Strong MACD crossover on daily chart. RSI at 58 — momentum intact without being overbought. Volume 1.8× above 20-day average. EMA(20) acting as dynamic support.', days_to_target:12 },
  { stock_symbol:'TATAMOTORS', company_name:'Tata Motors Ltd', action:'BUY', entry_price:910, stop_loss:884,
    target_price:972, quantity:10, risk_amount:260, potential_profit:620, potential_loss:260,
    risk_reward_ratio:2.38, confidence_score:.78,
    ai_reasoning:'Bullish flag pattern forming after breakout above ₹900 resistance. FIIs bought 1.2M shares this week. Sector tailwind from EV growth narrative.', days_to_target:18 },
  { stock_symbol:'AXISBANK', company_name:'Axis Bank Ltd', action:'SELL', entry_price:1042, stop_loss:1065,
    target_price:992, quantity:8, risk_amount:184, potential_profit:400, potential_loss:184,
    risk_reward_ratio:2.17, confidence_score:.71,
    ai_reasoning:'Bearish engulfing candle at key 1050 resistance. RSI divergence on H4 timeframe. Net FII selling in banking sector this week.', days_to_target:10 },
];

@Component({
  selector: 'app-dashboard',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, FormsModule],
  providers: [DecimalPipe, CurrencyPipe, PercentPipe],
  template: `
<!-- ── HEADER ──────────────────────────────────────────────────────── -->
<header class="header">
  <div class="header-inner">
    <div class="brand">
      <div class="brand-icon"><span class="material-icons-round">trending_up</span></div>
      <span class="brand-name">VanTrade</span>
      <span class="badge info market-badge">
        <span class="dot" [class.open]="marketOpen"></span>
        {{ marketOpen ? 'Market Open' : 'Market Closed' }}
      </span>
    </div>

    <!-- Index strip (scrolling) -->
    <div class="index-strip">
      <div class="ticker-track">
        @for (idx of indices(); track idx.symbol) {
          <div class="tick-item">
            <span class="sym">{{ idx.symbol }}</span>
            <span [class]="idx.change >= 0 ? 'text-profit' : 'text-loss'" class="val">
              {{ idx.ltp | number:'1.0-0' }}
            </span>
            <span [class]="idx.change >= 0 ? 'text-profit' : 'text-loss'" class="chg">
              {{ idx.change >= 0 ? '+' : '' }}{{ idx.changePct | number:'1.2-2' }}%
            </span>
          </div>
        }
        <!-- duplicate for seamless loop -->
        @for (idx of indices(); track 'd'+idx.symbol) {
          <div class="tick-item">
            <span class="sym">{{ idx.symbol }}</span>
            <span [class]="idx.change >= 0 ? 'text-profit' : 'text-loss'" class="val">
              {{ idx.ltp | number:'1.0-0' }}
            </span>
            <span [class]="idx.change >= 0 ? 'text-profit' : 'text-loss'" class="chg">
              {{ idx.change >= 0 ? '+' : '' }}{{ idx.changePct | number:'1.2-2' }}%
            </span>
          </div>
        }
      </div>
    </div>

    <div class="header-actions">
      <span class="user-chip">
        <span class="material-icons-round">account_circle</span>
        {{ user()?.name ?? 'User' }}
      </span>
      <button class="btn btn-ghost btn-sm icon-btn" (click)="refresh()" title="Refresh">
        <span class="material-icons-round" [class.spinning]="refreshing()">refresh</span>
      </button>
      <button class="btn btn-ghost btn-sm icon-btn" (click)="logout()" title="Logout">
        <span class="material-icons-round">logout</span>
      </button>
    </div>
  </div>
</header>

<!-- ── MAIN GRID ───────────────────────────────────────────────────── -->
<main class="main-grid stagger">

  <!-- ══ COL-LEFT: portfolio summary + analysis form ══════════════ -->
  <aside class="col-left">

    <!-- Portfolio Summary -->
    <section class="card portfolio-card">
      <div class="card-header">
        <span class="material-icons-round icon-blue">account_balance_wallet</span>
        <h4>Portfolio</h4>
      </div>

      <div class="balance-hero">
        <div class="balance-label">Total Value</div>
        <div class="balance-val">₹{{ totalValue() | number:'1.0-0' }}</div>
        <div [class]="totalPnl() >= 0 ? 'pnl-chip profit' : 'pnl-chip loss'">
          <span class="material-icons-round">{{ totalPnl() >= 0 ? 'arrow_upward' : 'arrow_downward' }}</span>
          {{ totalPnl() >= 0 ? '+' : '' }}₹{{ totalPnl() | number:'1.0-0' }}
          ({{ totalPnlPct() | number:'1.2-2' }}%)
        </div>
      </div>

      <div class="divider"></div>

      <div class="stat-grid">
        <div class="stat">
          <div class="stat-label">Invested</div>
          <div class="stat-val">₹{{ totalInvested() | number:'1.0-0' }}</div>
        </div>
        <div class="stat">
          <div class="stat-label">Day P&amp;L</div>
          <div class="stat-val" [class]="dayPnl() >= 0 ? 'text-profit' : 'text-loss'">
            {{ dayPnl() >= 0 ? '+' : '' }}₹{{ dayPnl() | number:'1.0-0' }}
          </div>
        </div>
        <div class="stat">
          <div class="stat-label">Available</div>
          <div class="stat-val text-info">₹{{ availBal() | number:'1.0-0' }}</div>
        </div>
        <div class="stat">
          <div class="stat-label">Holdings</div>
          <div class="stat-val">{{ holdings().length }}</div>
        </div>
      </div>

      <!-- Mini holdings bar -->
      @if (holdings().length) {
        <div class="mini-holdings">
          <div class="section-label" style="margin-top:16px">Holdings P&amp;L</div>
          @for (h of holdings().slice(0,4); track h.tradingsymbol) {
            <div class="mini-row">
              <span class="mini-sym">{{ h.tradingsymbol }}</span>
              <div class="mini-bar-wrap">
                <div class="mini-bar"
                     [style.width.%]="miniBarPct(h)"
                     [style.background]="h.pnl >= 0 ? 'var(--color-primary)' : 'var(--color-danger)'">
                </div>
              </div>
              <span [class]="h.pnl >= 0 ? 'text-profit mini-pnl' : 'text-loss mini-pnl'">
                {{ h.pnl >= 0 ? '+' : '' }}₹{{ h.pnl | number:'1.0-0' }}
              </span>
            </div>
          }
        </div>
      }
    </section>

    <!-- AI Analysis Form -->
    <section class="card analysis-card">
      <div class="card-header">
        <span class="material-icons-round icon-green">auto_awesome</span>
        <h4>AI Analysis</h4>
        @if (analysisResult()) {
          <span class="badge buy" style="margin-left:auto">{{ analysisResult()!.stocks.length }} signals</span>
        }
      </div>

      <div class="form-fields stagger">
        <div class="form-row">
          <label>Stocks</label>
          <input class="input-field" type="number" [(ngModel)]="form.num_stocks" min="1" max="10">
        </div>
        <div class="form-row">
          <label>Hold (days)</label>
          <select class="input-field" [(ngModel)]="form.hold_duration_days">
            <option [value]="0">Intraday</option>
            <option [value]="3">3 Days</option>
            <option [value]="7">1 Week</option>
            <option [value]="14">2 Weeks</option>
            <option [value]="30">1 Month</option>
          </select>
        </div>
        <div class="form-row">
          <label>Capital (₹)</label>
          <div class="input-field" style="background:var(--color-surface);color:var(--color-text-mid);cursor:default">
            ₹{{ availBal() | number:'1.0-0' }}
          </div>
        </div>
      </div>

      @if (analysisError()) {
        <div class="error-msg fade-in" style="margin-top:12px">
          <span class="material-icons-round">error_outline</span> {{ analysisError() }}
        </div>
      }

      <button class="btn btn-primary run-btn" (click)="runAnalysis()" [disabled]="analysing()">
        @if (analysing()) {
          <span class="spinner"></span> Analysing…
        } @else {
          <span class="material-icons-round">psychology</span> Run AI Analysis
        }
      </button>
    </section>

  </aside>

  <!-- ══ COL-CENTER: holdings + positions ═════════════════════════ -->
  <div class="col-center">

    <!-- Holdings -->
    <section class="card holdings-card">
      <div class="card-header">
        <span class="material-icons-round icon-indigo">business_center</span>
        <h4>Holdings</h4>
        <span class="count-badge">{{ holdings().length }}</span>
        @if (gttCount() > 0) {
          <span class="badge info" style="margin-left:auto;font-size:10px">
            <span class="material-icons-round" style="font-size:12px">verified</span>
            {{ gttCount() }} GTT active
          </span>
        }
      </div>

      <!-- GTT summary -->
      @if (gttProtectedCount() > 0) {
        <div class="gtt-summary">
          <div class="gtt-sum-item profit">
            <span class="material-icons-round">north</span>
            <div>
              <div class="gs-label">Expected Profit</div>
              <div class="gs-val">+₹{{ totalExpectedProfit() | number:'1.0-0' }}</div>
            </div>
          </div>
          <div class="gtt-sum-item loss">
            <span class="material-icons-round">south</span>
            <div>
              <div class="gs-label">Max Loss Protected</div>
              <div class="gs-val">-₹{{ totalExpectedLoss() | number:'1.0-0' }}</div>
            </div>
          </div>
        </div>
      }

      <div class="holdings-list">
        @for (h of holdings(); track h.tradingsymbol; let i = $index) {
          <div class="holding-row" [style.animation-delay]="i*50 + 'ms'">
            <div class="holding-left">
              <div class="sym-circle" [style.background]="symColor(h.tradingsymbol)">
                {{ h.tradingsymbol.charAt(0) }}
              </div>
              <div>
                <div class="h-sym">{{ h.tradingsymbol }}</div>
                <div class="h-co">{{ h.company }}</div>
              </div>
            </div>

            <div class="holding-stats">
              <div class="h-stat">
                <div class="hs-label">Qty</div>
                <div class="hs-val">{{ h.quantity }}</div>
              </div>
              <div class="h-stat">
                <div class="hs-label">Avg</div>
                <div class="hs-val">₹{{ h.average_price | number:'1.0-0' }}</div>
              </div>
              <div class="h-stat">
                <div class="hs-label">LTP</div>
                <div class="hs-val">₹{{ h.last_price | number:'1.0-0' }}</div>
              </div>
              <div class="h-stat">
                <div class="hs-label">P&amp;L</div>
                <div class="hs-val" [class]="h.pnl >= 0 ? 'text-profit text-bold' : 'text-loss text-bold'">
                  {{ h.pnl >= 0 ? '+' : '' }}₹{{ h.pnl | number:'1.0-0' }}
                </div>
              </div>
            </div>

            @if (h.has_gtt) {
              <div class="gtt-chips">
                <span class="gtt-chip profit">
                  <span class="material-icons-round">north</span>₹{{ h.max_profit! | number:'1.0-0' }}
                </span>
                <span class="gtt-chip loss">
                  <span class="material-icons-round">south</span>₹{{ h.max_loss! | number:'1.0-0' }}
                </span>
              </div>
            } @else {
              <span class="no-gtt">No GTT</span>
            }
          </div>
        }
      </div>
    </section>

    <!-- Open Positions -->
    @if (positions().length > 0) {
      <section class="card positions-card">
        <div class="card-header">
          <span class="material-icons-round icon-orange">show_chart</span>
          <h4>Open Positions</h4>
          <span class="count-badge">{{ positions().length }}</span>
          <div [class]="positionsPnl() >= 0 ? 'header-pnl profit' : 'header-pnl loss'" style="margin-left:auto">
            {{ positionsPnl() >= 0 ? '+' : '' }}₹{{ positionsPnl() | number:'1.0-0' }}
          </div>
        </div>

        <div class="positions-table">
          <div class="pt-header">
            <span>Symbol</span><span>Product</span><span>Qty</span>
            <span>Avg Price</span><span>LTP</span><span>P&amp;L</span>
          </div>
          @for (p of positions(); track p.tradingsymbol) {
            <div class="pt-row">
              <span class="pt-sym">{{ p.tradingsymbol }}</span>
              <span><span class="badge info" style="font-size:10px">{{ p.product }}</span></span>
              <span>{{ p.quantity }}</span>
              <span>₹{{ p.average_price | number:'1.2-2' }}</span>
              <span>₹{{ p.last_price | number:'1.2-2' }}</span>
              <span [class]="p.pnl >= 0 ? 'text-profit text-bold' : 'text-loss text-bold'">
                {{ p.pnl >= 0 ? '+' : '' }}₹{{ p.pnl | number:'1.0-0' }}
              </span>
            </div>
          }
        </div>
      </section>
    }

    <!-- Active GTTs table -->
    @if (gtts().length > 0) {
      <section class="card gtt-card">
        <div class="card-header">
          <span class="material-icons-round icon-secondary">alarm_on</span>
          <h4>Active GTTs</h4>
          <span class="count-badge">{{ gtts().length }}</span>
        </div>
        <div class="positions-table">
          <div class="pt-header">
            <span>Symbol</span><span>Qty</span>
            <span>Stop Loss</span><span>Target</span><span>LTP</span><span>Status</span>
          </div>
          @for (g of gtts(); track g.id) {
            <div class="pt-row">
              <span class="pt-sym">{{ g.tradingsymbol }}</span>
              <span>{{ g.quantity }}</span>
              <span class="text-loss">₹{{ g.trigger_values[0] | number:'1.0-0' }}</span>
              <span class="text-profit">₹{{ g.trigger_values[1] | number:'1.0-0' }}</span>
              <span>₹{{ g.last_price | number:'1.0-0' }}</span>
              <span><span class="badge buy" style="font-size:10px">{{ g.status }}</span></span>
            </div>
          }
        </div>
      </section>
    }
  </div>

  <!-- ══ COL-RIGHT: AI results ═════════════════════════════════════ -->
  <aside class="col-right">

    @if (analysisResult()) {
      <!-- Overall Confidence -->
      <section class="card confidence-card scale-in">
        <div class="card-header">
          <span class="material-icons-round icon-green">verified_outlined</span>
          <h4>Overall Confidence</h4>
        </div>
        <div class="conf-display">
          <div class="conf-ring" [style.--pct]="overallConfidence() + '%'">
            <svg viewBox="0 0 80 80">
              <circle cx="40" cy="40" r="32" fill="none" stroke="var(--color-divider)" stroke-width="7"/>
              <circle cx="40" cy="40" r="32" fill="none"
                      [attr.stroke]="confColor()" stroke-width="7"
                      stroke-linecap="round"
                      [attr.stroke-dasharray]="201"
                      [attr.stroke-dashoffset]="201 - (overallConfidence()/100)*201"
                      transform="rotate(-90 40 40)"
                      style="transition:stroke-dashoffset .8s ease"/>
            </svg>
            <div class="conf-center">
              <div class="conf-pct" [style.color]="confColor()">{{ overallConfPct() }}%</div>
              <div class="conf-lbl">{{ confLabel() }}</div>
            </div>
          </div>
          <div class="conf-meta">
            <div class="cm-row">
              <span class="material-icons-round text-profit" style="font-size:16px">check_circle</span>
              <span>{{ analysisResult()!.stocks.length }} signals generated</span>
            </div>
            <div class="cm-row">
              <span class="material-icons-round text-info" style="font-size:16px">account_balance</span>
              <span>₹{{ analysisResult()!.portfolio_metrics.total_investment | number:'1.0-0' }} to deploy</span>
            </div>
            <div class="cm-row">
              <span class="material-icons-round text-profit" style="font-size:16px">trending_up</span>
              <span>Max profit ₹{{ analysisResult()!.portfolio_metrics.max_profit | number:'1.0-0' }}</span>
            </div>
            <div class="cm-row">
              <span class="material-icons-round text-loss" style="font-size:16px">trending_down</span>
              <span>Max loss ₹{{ analysisResult()!.portfolio_metrics.max_loss | number:'1.0-0' }}</span>
            </div>
          </div>
        </div>
      </section>

      <!-- Stock Cards -->
      <section class="card signals-card scale-in">
        <div class="card-header">
          <span class="material-icons-round icon-green">psychology</span>
          <h4>AI Signals</h4>
          <button class="btn btn-primary btn-sm execute-btn" (click)="executeAll()" style="margin-left:auto">
            <span class="material-icons-round">bolt</span> Execute All
          </button>
        </div>

        <div class="signals-list">
          @for (s of analysisResult()!.stocks; track s.stock_symbol; let i = $index) {
            <div class="signal-card" [style.animation-delay]="i*80 + 'ms'"
                 [class.expanded]="expandedSignal() === s.stock_symbol"
                 (click)="toggleSignal(s.stock_symbol)">

              <div class="sc-top">
                <div class="sc-left">
                  <span [class]="'badge ' + s.action.toLowerCase()">{{ s.action }}</span>
                  <div>
                    <div class="sc-sym">{{ s.stock_symbol }}</div>
                    <div class="sc-co">{{ s.company_name }}</div>
                  </div>
                </div>
                <div class="sc-right">
                  <div class="sc-conf" [style.color]="signalColor(s)">
                    {{ (s.confidence_score * 100).toFixed(0) }}%
                  </div>
                  <span class="material-icons-round expand-icon">
                    {{ expandedSignal() === s.stock_symbol ? 'expand_less' : 'expand_more' }}
                  </span>
                </div>
              </div>

              <!-- Confidence bar -->
              <div class="progress-bar-wrap" style="margin:8px 0 4px">
                <div class="progress-fill"
                     [style.width.%]="s.confidence_score * 100"
                     [style.background]="signalColor(s)">
                </div>
              </div>

              <!-- Price row -->
              <div class="price-row">
                <div class="pr-item">
                  <div class="pr-label">Entry</div>
                  <div class="pr-val">₹{{ s.entry_price | number:'1.0-0' }}</div>
                </div>
                <span class="material-icons-round pr-arrow">arrow_forward</span>
                <div class="pr-item">
                  <div class="pr-label">SL</div>
                  <div class="pr-val text-loss">₹{{ s.stop_loss | number:'1.0-0' }}</div>
                </div>
                <span class="material-icons-round pr-arrow">arrow_forward</span>
                <div class="pr-item">
                  <div class="pr-label">Target</div>
                  <div class="pr-val text-profit">₹{{ s.target_price | number:'1.0-0' }}</div>
                </div>
              </div>

              <!-- Expanded detail -->
              @if (expandedSignal() === s.stock_symbol) {
                <div class="sc-detail fade-in">
                  <div class="detail-grid">
                    <div class="dg-item">
                      <div class="dg-label">Qty</div>
                      <div class="dg-val">{{ s.quantity }}</div>
                    </div>
                    <div class="dg-item">
                      <div class="dg-label">Risk</div>
                      <div class="dg-val text-loss">₹{{ s.risk_amount | number:'1.0-0' }}</div>
                    </div>
                    <div class="dg-item">
                      <div class="dg-label">Profit</div>
                      <div class="dg-val text-profit">₹{{ s.potential_profit | number:'1.0-0' }}</div>
                    </div>
                    <div class="dg-item">
                      <div class="dg-label">R:R</div>
                      <div class="dg-val">1:{{ s.risk_reward_ratio | number:'1.1-1' }}</div>
                    </div>
                  </div>
                  <div class="reasoning">
                    <span class="material-icons-round" style="font-size:14px;color:var(--color-text-mid)">smart_toy</span>
                    {{ s.ai_reasoning }}
                  </div>
                  <div class="sc-actions">
                    <button class="btn btn-primary btn-sm" (click)="executeOne(s);$event.stopPropagation()">
                      <span class="material-icons-round">bolt</span> Execute
                    </button>
                    <button class="btn btn-ghost btn-sm" (click)="$event.stopPropagation()">
                      Skip
                    </button>
                  </div>
                </div>
              }
            </div>
          }
        </div>
      </section>

    } @else {
      <!-- Empty state for analysis -->
      <section class="card empty-analysis scale-in">
        <div class="ea-inner">
          <div class="ea-icon">
            <span class="material-icons-round">psychology</span>
          </div>
          <h4>Ready to Analyse</h4>
          <p>Configure parameters on the left and run the AI analysis to see trade signals here.</p>
          <div class="ea-steps">
            <div class="ea-step">
              <span class="step-num">1</span>Set number of stocks &amp; hold period
            </div>
            <div class="ea-step">
              <span class="step-num">2</span>Adjust risk % and capital
            </div>
            <div class="ea-step">
              <span class="step-num">3</span>Click "Run AI Analysis"
            </div>
          </div>
        </div>
      </section>
    }

  </aside>
</main>

<!-- ── TOAST ───────────────────────────────────────────────────────── -->
@if (toast()) {
  <div class="toast" [class]="toast()!.type" [@.disabled]="true">
    <span class="material-icons-round">{{ toast()!.type === 'success' ? 'check_circle' : 'error' }}</span>
    {{ toast()!.msg }}
  </div>
}
  `,
  styles: [`
  /* ── Layout ──────────────────────────────────────────────────────── */
  :host { display: block; min-height: 100vh; }

  .header {
    position: sticky; top: 0; z-index: 100;
    background: var(--color-secondary);
    box-shadow: 0 2px 12px rgba(0,0,0,.2);
  }
  .header-inner {
    max-width: 1600px; margin: 0 auto;
    display: flex; align-items: center; gap: 16px;
    padding: 0 20px; height: 56px;
  }

  .brand { display: flex; align-items: center; gap: 10px; flex-shrink: 0; }
  .brand-icon {
    width: 34px; height: 34px; border-radius: 9px;
    background: rgba(255,255,255,.15);
    display: flex; align-items: center; justify-content: center;
    .material-icons-round { color: white; font-size: 20px; }
  }
  .brand-name { color: white; font-weight: 800; font-size: 18px; }
  .market-badge { font-size: 10px !important; padding: 2px 8px !important; }
  .dot {
    width: 6px; height: 6px; border-radius: 50%;
    background: var(--color-danger); flex-shrink: 0;
    &.open { background: var(--color-primary); animation: pulse-dot 1.4s ease-in-out infinite; }
  }

  /* Index ticker */
  .index-strip {
    flex: 1; overflow: hidden; height: 100%;
    display: flex; align-items: center;
    mask-image: linear-gradient(90deg,transparent,black 60px,black calc(100% - 60px),transparent);
  }
  .ticker-track {
    display: flex; gap: 0; white-space: nowrap;
    animation: ticker-scroll 24s linear infinite;
    &:hover { animation-play-state: paused; }
  }
  .tick-item {
    display: flex; align-items: center; gap: 8px;
    padding: 0 24px; border-right: 1px solid rgba(255,255,255,.15);
    .sym { color: rgba(255,255,255,.7); font-size: 11px; font-weight: 600; letter-spacing: .5px; }
    .val { color: white; font-size: 13px; font-weight: 700; }
    .chg { font-size: 11px; font-weight: 600; }
  }

  .header-actions { display: flex; align-items: center; gap: 6px; flex-shrink: 0; }
  .user-chip {
    display: flex; align-items: center; gap: 6px;
    color: rgba(255,255,255,.85); font-size: 13px; font-weight: 500;
    .material-icons-round { font-size: 20px; }
  }
  .icon-btn { color: rgba(255,255,255,.7) !important; &:hover { color: white !important; background: rgba(255,255,255,.1) !important; } }

  /* Main grid */
  .main-grid {
    max-width: 1600px; margin: 0 auto;
    display: grid;
    grid-template-columns: 300px 1fr 340px;
    grid-template-areas: "left center right";
    gap: 16px; padding: 16px 20px 32px;
  }
  .col-left   { grid-area: left;   display: flex; flex-direction: column; gap: 16px; }
  .col-center { grid-area: center; display: flex; flex-direction: column; gap: 16px; }
  .col-right  { grid-area: right;  display: flex; flex-direction: column; gap: 16px; }

  /* ── Card chrome ──────────────────────────────────────────────── */
  .card-header {
    display: flex; align-items: center; gap: 8px; margin-bottom: 16px;
    h4 { font-size: 15px; font-weight: 700; }
  }
  .count-badge {
    display: inline-flex; align-items: center; justify-content: center;
    min-width: 22px; height: 22px; padding: 0 6px; border-radius: 11px;
    background: var(--color-background); color: var(--color-text-mid);
    font-size: 11px; font-weight: 700;
  }
  .icon-green     { color: var(--color-primary);   }
  .icon-blue      { color: var(--color-info);       }
  .icon-indigo    { color: var(--color-secondary);  }
  .icon-orange    { color: var(--color-warning);    }
  .icon-secondary { color: var(--color-secondary);  }

  /* ── Portfolio card ───────────────────────────────────────────── */
  .balance-hero { text-align: center; padding: 12px 0 16px; }
  .balance-label { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; color: var(--color-text-low); }
  .balance-val { font-size: 30px; font-weight: 800; color: var(--color-text); margin: 4px 0; }
  .pnl-chip {
    display: inline-flex; align-items: center; gap: 4px;
    padding: 4px 12px; border-radius: var(--radius-pill);
    font-size: 13px; font-weight: 700;
    .material-icons-round { font-size: 14px; }
    &.profit { background: var(--color-primary-surface); color: var(--color-primary); }
    &.loss   { background: var(--color-danger-surface);  color: var(--color-danger);  }
  }
  .stat-grid {
    display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-top: 4px;
  }
  .stat {
    background: var(--color-background); border-radius: var(--radius-md); padding: 10px 12px;
    .stat-label { font-size: 10px; font-weight: 600; text-transform: uppercase; letter-spacing: .5px; color: var(--color-text-low); margin-bottom: 4px; }
    .stat-val   { font-size: 15px; font-weight: 700; color: var(--color-text); }
  }
  .mini-holdings { margin-top: 4px; }
  .mini-row { display: flex; align-items: center; gap: 8px; margin-bottom: 8px; }
  .mini-sym { font-size: 11px; font-weight: 600; width: 60px; flex-shrink: 0; }
  .mini-bar-wrap { flex: 1; height: 4px; background: var(--color-divider); border-radius: 2px; overflow: hidden; }
  .mini-bar { height: 100%; border-radius: 2px; min-width: 4px; transition: width .6s ease; }
  .mini-pnl { font-size: 11px; font-weight: 600; width: 60px; text-align: right; flex-shrink: 0; }

  /* ── Analysis form ────────────────────────────────────────────── */
  .form-fields { display: flex; flex-direction: column; gap: 10px; }
  .form-row {
    display: flex; align-items: center; justify-content: space-between; gap: 8px;
    label { font-size: 12px; font-weight: 600; color: var(--color-text-high); flex-shrink: 0; width: 80px; }
    .input-field { padding: 7px 10px; font-size: 13px; }
  }
  .error-msg {
    display: flex; align-items: center; gap: 8px;
    background: var(--color-danger-surface); color: var(--color-danger);
    border: 1px solid var(--color-danger-border);
    padding: 10px 14px; border-radius: var(--radius-md); font-size: 12px; margin-top: 4px;
    .material-icons-round { font-size: 16px; }
  }
  .run-btn { width: 100%; margin-top: 14px; padding: 12px; }
  .spinner {
    width: 14px; height: 14px; border: 2px solid rgba(255,255,255,.35);
    border-top-color: white; border-radius: 50%; animation: spin .7s linear infinite;
  }

  /* ── Holdings ─────────────────────────────────────────────────── */
  .gtt-summary {
    display: flex; gap: 10px; margin-bottom: 16px;
  }
  .gtt-sum-item {
    flex: 1; display: flex; align-items: center; gap: 8px;
    padding: 10px 12px; border-radius: var(--radius-md); border: 1px solid;
    .material-icons-round { font-size: 18px; }
    .gs-label { font-size: 10px; font-weight: 600; text-transform: uppercase; letter-spacing: .4px; margin-bottom: 2px; }
    .gs-val   { font-size: 14px; font-weight: 700; }
    &.profit { background: var(--color-primary-surface); border-color: var(--color-primary-border); color: var(--color-primary); }
    &.loss   { background: var(--color-danger-surface);  border-color: var(--color-danger-border);  color: var(--color-danger);  }
  }
  .holdings-list { display: flex; flex-direction: column; gap: 2px; }
  .holding-row {
    display: flex; align-items: center; gap: 12px;
    padding: 12px; border-radius: var(--radius-md);
    border: 1px solid transparent;
    transition: all var(--duration-fast) var(--ease);
    animation: fadeSlideUp var(--duration-slow) var(--ease) both;
    &:hover { background: var(--color-background); border-color: var(--color-divider); }
  }
  .holding-left { display: flex; align-items: center; gap: 10px; flex: 0 0 180px; }
  .sym-circle {
    width: 36px; height: 36px; border-radius: 10px; flex-shrink: 0;
    display: flex; align-items: center; justify-content: center;
    color: white; font-size: 14px; font-weight: 700;
  }
  .h-sym { font-size: 13px; font-weight: 700; }
  .h-co  { font-size: 11px; color: var(--color-text-mid); }
  .holding-stats { display: flex; gap: 12px; flex: 1; }
  .h-stat { text-align: right; }
  .hs-label { font-size: 10px; color: var(--color-text-low); }
  .hs-val   { font-size: 13px; font-weight: 600; }
  .gtt-chips { display: flex; flex-direction: column; gap: 4px; flex-shrink: 0; }
  .gtt-chip {
    display: flex; align-items: center; gap: 2px;
    padding: 2px 7px; border-radius: var(--radius-pill); font-size: 10px; font-weight: 700;
    .material-icons-round { font-size: 11px; }
    &.profit { background: var(--color-primary-surface); color: var(--color-primary); }
    &.loss   { background: var(--color-danger-surface);  color: var(--color-danger);  }
  }
  .no-gtt { font-size: 10px; color: var(--color-text-low); white-space: nowrap; }

  /* ── Positions / GTT table ────────────────────────────────────── */
  .positions-table { font-size: 12px; }
  .pt-header, .pt-row {
    display: grid; grid-template-columns: 2fr 1fr 1fr 1.2fr 1.2fr 1.2fr;
    align-items: center; gap: 8px; padding: 8px 4px;
  }
  .pt-header { color: var(--color-text-low); font-weight: 600; font-size: 10px; text-transform: uppercase; letter-spacing: .5px; border-bottom: 1px solid var(--color-divider); }
  .pt-row { border-bottom: 1px solid rgba(0,0,0,.03); transition: background var(--duration-fast); &:hover { background: var(--color-background); } }
  .pt-sym { font-weight: 700; font-size: 12px; }

  /* ── Confidence ───────────────────────────────────────────────── */
  .conf-display { display: flex; align-items: center; gap: 20px; }
  .conf-ring { position: relative; width: 100px; height: 100px; flex-shrink: 0; }
  .conf-ring svg { width: 100%; height: 100%; }
  .conf-center {
    position: absolute; inset: 0; display: flex; flex-direction: column;
    align-items: center; justify-content: center;
  }
  .conf-pct { font-size: 22px; font-weight: 800; line-height: 1; }
  .conf-lbl { font-size: 10px; font-weight: 600; text-transform: uppercase; letter-spacing: .5px; color: var(--color-text-mid); }
  .conf-meta { flex: 1; display: flex; flex-direction: column; gap: 8px; }
  .cm-row { display: flex; align-items: center; gap: 8px; font-size: 12px; color: var(--color-text-mid); }

  /* ── Signal cards ─────────────────────────────────────────────── */
  .signals-list { display: flex; flex-direction: column; gap: 8px; }
  .signal-card {
    border: 1.5px solid var(--color-divider); border-radius: var(--radius-lg);
    padding: 12px; cursor: pointer;
    transition: all var(--duration-fast) var(--ease);
    animation: fadeSlideUp var(--duration-slow) var(--ease) both;
    &:hover { border-color: var(--color-primary); box-shadow: 0 2px 12px rgba(56,142,60,.12); }
    &.expanded { border-color: var(--color-primary); background: var(--color-primary-surface); }
  }
  .sc-top  { display: flex; align-items: center; justify-content: space-between; margin-bottom: 6px; }
  .sc-left { display: flex; align-items: center; gap: 8px; }
  .sc-sym  { font-size: 14px; font-weight: 700; }
  .sc-co   { font-size: 10px; color: var(--color-text-mid); }
  .sc-right { display: flex; align-items: center; gap: 4px; }
  .sc-conf { font-size: 16px; font-weight: 800; }
  .expand-icon { font-size: 18px; color: var(--color-text-mid); }
  .price-row { display: flex; align-items: center; gap: 4px; margin-top: 8px; }
  .pr-item { flex: 1; text-align: center; }
  .pr-label { font-size: 9px; text-transform: uppercase; letter-spacing: .5px; color: var(--color-text-low); }
  .pr-val   { font-size: 13px; font-weight: 700; }
  .pr-arrow { font-size: 14px; color: var(--color-text-low); flex-shrink: 0; }
  .sc-detail { margin-top: 12px; padding-top: 12px; border-top: 1px solid rgba(0,0,0,.06); }
  .detail-grid { display: grid; grid-template-columns: 1fr 1fr 1fr 1fr; gap: 8px; margin-bottom: 10px; }
  .dg-item { text-align: center; }
  .dg-label { font-size: 9px; text-transform: uppercase; letter-spacing: .5px; color: var(--color-text-low); }
  .dg-val   { font-size: 13px; font-weight: 700; }
  .reasoning {
    font-size: 12px; color: var(--color-text-mid); line-height: 1.6;
    background: rgba(0,0,0,.03); border-radius: var(--radius-md); padding: 10px;
    display: flex; gap: 6px; align-items: flex-start;
  }
  .sc-actions { display: flex; gap: 8px; margin-top: 10px; }
  .execute-btn { font-size: 12px; }

  /* ── Empty analysis ───────────────────────────────────────────── */
  .empty-analysis { flex: 1; }
  .ea-inner { text-align: center; padding: 24px 16px; }
  .ea-icon {
    width: 72px; height: 72px; border-radius: 20px; margin: 0 auto 16px;
    background: var(--color-primary-surface);
    display: flex; align-items: center; justify-content: center;
    .material-icons-round { font-size: 36px; color: var(--color-primary); }
  }
  .ea-inner h4 { font-size: 16px; font-weight: 700; margin-bottom: 8px; }
  .ea-inner p  { font-size: 13px; color: var(--color-text-mid); line-height: 1.6; margin-bottom: 20px; }
  .ea-steps { display: flex; flex-direction: column; gap: 10px; text-align: left; }
  .ea-step  { display: flex; align-items: center; gap: 10px; font-size: 13px; color: var(--color-text-mid); }
  .step-num {
    width: 22px; height: 22px; border-radius: 50%; flex-shrink: 0;
    background: var(--color-primary); color: white;
    display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: 700;
  }

  /* ── Toast ────────────────────────────────────────────────────── */
  .toast {
    position: fixed; bottom: 24px; right: 24px; z-index: 9999;
    display: flex; align-items: center; gap: 8px;
    padding: 12px 20px; border-radius: var(--radius-lg);
    font-size: 13px; font-weight: 600; box-shadow: var(--shadow-raised);
    animation: fadeSlideUp .3s ease both;
    &.success { background: var(--color-primary); color: white; }
    &.error   { background: var(--color-danger);  color: white; }
    .material-icons-round { font-size: 18px; }
  }

  /* ── Misc ─────────────────────────────────────────────────────── */
  .header-pnl {
    font-size: 13px; font-weight: 700; padding: 3px 10px;
    border-radius: var(--radius-pill);
    &.profit { background: var(--color-primary-surface); color: var(--color-primary); }
    &.loss   { background: var(--color-danger-surface);  color: var(--color-danger);  }
  }
  .spinning { animation: spin .7s linear infinite; }
  .portfolio-card { overflow: hidden; }

  /* ── Responsive ───────────────────────────────────────────────── */
  @media (max-width: 1280px) {
    .main-grid { grid-template-columns: 280px 1fr 300px; }
  }
  @media (max-width: 1024px) {
    .main-grid {
      grid-template-columns: 1fr 1fr;
      grid-template-areas: "left right" "center center";
    }
  }
  @media (max-width: 720px) {
    .main-grid {
      grid-template-columns: 1fr;
      grid-template-areas: "left" "right" "center";
      padding: 12px;
    }
    .index-strip { display: none; }
    .holding-stats { display: none; }
    .holding-left { flex: 1; }
  }
  `]
})
export class DashboardComponent implements OnInit, OnDestroy {
  private auth   = inject(AuthService);
  private api    = inject(ApiService);
  private router = inject(Router);

  user = this.auth.user;

  /* ── State ── */
  holdings     = signal<Holding[]>([]);
  positions    = signal<Position[]>([]);
  gtts         = signal<Gtt[]>([]);
  analysisResult = signal<AnalysisResult | null>(null);
  expandedSignal = signal<string | null>(null);
  refreshing   = signal(false);
  analysing    = signal(false);
  analysisError = signal('');
  toast        = signal<{ msg: string; type: 'success' | 'error' } | null>(null);

  indices = signal<{ symbol: string; ltp: number; change: number; changePct: number }[]>([
    { symbol: 'NIFTY 50',    ltp: 24850.30, change:  185.4, changePct:  0.75 },
    { symbol: 'BANKNIFTY',   ltp: 52318.60, change: -124.5, changePct: -0.24 },
    { symbol: 'NIFTY IT',    ltp: 41290.10, change:  320.8, changePct:  0.78 },
    { symbol: 'NIFTY FMCG',  ltp: 56840.20, change:   92.3, changePct:  0.16 },
    { symbol: 'SENSEX',      ltp: 81720.40, change:  540.2, changePct:  0.66 },
  ]);

  get marketOpen(): boolean {
    const now = new Date();
    const h = now.getHours(), m = now.getMinutes();
    const total = h * 60 + m;
    return total >= 555 && total < 915; // 9:15 – 15:15
  }

  form = { num_stocks: 3, hold_duration_days: 0, risk_percent: 1 };

  /* ── Computed ── */
  totalValue   = computed(() => this.totalInvested() + this.totalPnl());
  totalInvested = computed(() => this.holdings().reduce((s, h) => s + h.invested, 0));
  totalPnl      = computed(() => this.holdings().reduce((s, h) => s + h.pnl, 0)
                                 + this.positions().reduce((s, p) => s + p.pnl, 0));
  totalPnlPct   = computed(() => this.totalInvested() > 0 ? (this.totalPnl() / this.totalInvested()) * 100 : 0);
  dayPnl        = computed(() => this.holdings().reduce((s, h) => s + (h.day_change ?? 0), 0));
  availBal      = signal(250000);
  positionsPnl  = computed(() => this.positions().reduce((s, p) => s + p.pnl, 0));
  gttCount      = computed(() => this.gtts().length);
  gttProtectedCount = computed(() => this.holdings().filter(h => h.has_gtt).length);
  totalExpectedProfit = computed(() => this.holdings().filter(h => h.has_gtt).reduce((s, h) => s + (h.max_profit ?? 0), 0));
  totalExpectedLoss   = computed(() => this.holdings().filter(h => h.has_gtt).reduce((s, h) => s + (h.max_loss ?? 0), 0));

  overallConfidence = computed(() => {
    const s = this.analysisResult()?.stocks ?? [];
    return s.length ? s.reduce((sum, x) => sum + x.confidence_score, 0) / s.length * 100 : 0;
  });
  overallConfPct = computed(() => Math.round(this.overallConfidence()));
  confLabel      = computed(() => this.overallConfPct() >= 80 ? 'High' : this.overallConfPct() >= 70 ? 'Moderate' : 'Low');
  confColor      = computed(() => this.overallConfPct() >= 80 ? '#388E3C' : this.overallConfPct() >= 70 ? '#F57C00' : '#E53935');

  private sub?: Subscription;
  dataError = signal('');

  ngOnInit() {
    this.loadData();
    this.loadIndexPrices();
    // Auto-refresh every 60 s (market hours only)
    this.sub = interval(60000).subscribe(() => {
      this.loadData();
      this.loadIndexPrices();
    });
  }

  ngOnDestroy() { this.sub?.unsubscribe(); }

  /** Load dashboard + holdings from the real backend (or demo seed data). */
  private loadData() {
    if (this.isDemo()) {
      this.holdings.set(DEMO_HOLDINGS);
      this.positions.set(DEMO_POSITIONS);
      this.gtts.set(DEMO_GTTS);
      this.availBal.set(250000);
      return;
    }

    // ── Dashboard summary (balance, positions, GTTs) ──
    this.api.getDashboardSummary().subscribe({
      next: (res: any) => {
        this.availBal.set(res.available_balance ?? 0);
        this.positions.set((res.positions ?? res.open_positions ?? []).map((p: any) => ({
          tradingsymbol: p.symbol ?? p.tradingsymbol ?? '',
          product:       p.product ?? '',
          quantity:      p.quantity ?? 0,
          average_price: p.avg_price ?? p.average_price ?? 0,
          last_price:    p.ltp ?? p.last_price ?? 0,
          pnl:           p.pnl ?? 0,
          realised:      p.realised ?? 0,
          unrealised:    p.unrealised ?? p.pnl ?? 0,
        })));
        this.gtts.set((res.gtts ?? res.active_gtts ?? []).map((g: any) => ({
          ...g,
          tradingsymbol: g.symbol ?? g.tradingsymbol ?? '',
          id:            g.gtt_id ?? g.id,
        })));
        this.dataError.set('');
      },
      error: err => {
        const msg: string = err?.error?.detail ?? '';
        if (err.status === 401 || msg.toLowerCase().includes('session expired')) {
          this.showToast('Session expired — please log in again.', 'error');
          setTimeout(() => this.logout(), 2000);
        } else {
          this.dataError.set('Could not load dashboard data.');
        }
      }
    });

    // ── Holdings (separate endpoint, includes GTT stop/target) ──
    this.api.getHoldings().subscribe({
      next: (res: any) => {
        const raw: any[] = res.holdings ?? [];
        // Backend returns "symbol" not "tradingsymbol"; "invested_value"/"current_value" pre-computed
        this.holdings.set(raw.filter((h: any) => !!(h.symbol || h.tradingsymbol)).map((h: any) => ({
          tradingsymbol:   h.symbol ?? h.tradingsymbol,
          company:         h.company_name ?? h.symbol ?? h.tradingsymbol,
          quantity:        h.quantity ?? 0,
          average_price:   h.average_price ?? 0,
          last_price:      h.last_price ?? 0,
          pnl:             h.pnl ?? 0,
          pnl_pct:         h.pnl_pct ?? h.day_change_percentage ?? 0,
          day_change:      h.day_change ?? 0,
          day_change_pct:  h.day_change_pct ?? 0,
          invested:        h.invested_value ?? (h.average_price ?? 0) * (h.quantity ?? 0),
          current_value:   h.current_value ?? (h.last_price ?? 0) * (h.quantity ?? 0),
          stop_loss:       h.stop_loss ?? 0,
          target:          h.target ?? 0,
          max_profit:      h.max_profit ?? 0,
          max_loss:        h.max_loss ?? 0,
          has_gtt:         !!(h.has_gtt || h.gtt_id),
          gtt_id:          h.gtt_id,
        })));
      },
      error: () => {}
    });
  }

  /** Fetch NIFTY 50, BANKNIFTY live prices from the backend snapshot. */
  private loadIndexPrices() {
    if (this.isDemo()) return;
    // NIFTY 50 = 256265, BANKNIFTY = 260105, NIFTY IT = 5633600
    this.api.getSnapshot('256265,260105').subscribe({
      next: (res: any) => {
        const snap = res.snapshot ?? {};
        const n50  = snap['256265'];
        const bnk  = snap['260105'];
        const updated = [...this.indices()];
        if (n50) updated[0] = { symbol: 'NIFTY 50',  ltp: n50.last_price, change: n50.change ?? 0, changePct: n50.change_percent ?? 0 };
        if (bnk) updated[1] = { symbol: 'BANKNIFTY', ltp: bnk.last_price, change: bnk.change ?? 0, changePct: bnk.change_percent ?? 0 };
        this.indices.set(updated);
      },
      error: () => {}
    });
  }

  private isDemo() { return this.auth.user()?.userId === 'demo'; }

  refresh() {
    this.refreshing.set(true);
    this.loadData();
    this.loadIndexPrices();
    setTimeout(() => this.refreshing.set(false), 1000);
  }

  runAnalysis() {
    if (this.isDemo()) {
      this.analysing.set(true);
      setTimeout(() => {
        this.analysisResult.set({
          analysis_id: 'demo-001',
          status: 'PENDING_CONFIRMATION',
          stocks: DEMO_STOCKS,
          portfolio_metrics: {
            total_investment: DEMO_STOCKS.reduce((s, x) => s + x.entry_price * x.quantity, 0),
            total_risk:       DEMO_STOCKS.reduce((s, x) => s + x.risk_amount, 0),
            max_profit:       DEMO_STOCKS.reduce((s, x) => s + x.potential_profit, 0),
            max_loss:         DEMO_STOCKS.reduce((s, x) => s + x.potential_loss, 0),
          },
          available_balance: 250000,
          created_at: new Date().toISOString(),
        });
        this.analysing.set(false);
      }, 2200);
      return;
    }

    this.analysing.set(true);
    this.analysisError.set('');
    this.api.runAnalysis({ ...this.form, capital_to_use: this.availBal(), sectors: ['ALL'] }).subscribe({
      next: (res: any) => {
        this.analysisResult.set(res);
        this.analysing.set(false);
      },
      error: err => {
        this.analysisError.set(err?.error?.detail ?? 'Analysis failed. Try again.');
        this.analysing.set(false);
      }
    });
  }

  executeAll() {
    const result = this.analysisResult();
    if (!result) return;
    if (this.isDemo()) {
      this.showToast(`Demo: ${result.stocks.length} orders would be queued`, 'success');
      return;
    }
    this.api.confirmAnalysis(result.analysis_id, this.form.hold_duration_days).subscribe({
      next: () => this.showToast(`${result.stocks.length} orders queued for execution`, 'success'),
      error: err => this.showToast(err?.error?.detail ?? 'Execution failed', 'error'),
    });
  }

  toggleSignal(sym: string) {
    this.expandedSignal.set(this.expandedSignal() === sym ? null : sym);
  }

  executeOne(s: StockAnalysis) {
    this.showToast(`${s.action} ${s.stock_symbol} @ ₹${s.entry_price} — queued`, 'success');
  }

  logout() { this.auth.logout(); this.router.navigate(['/login']); }

  signalColor(s: StockAnalysis): string {
    const p = s.confidence_score * 100;
    return p >= 80 ? '#388E3C' : p >= 70 ? '#F57C00' : '#E53935';
  }

  miniBarPct(h: Holding): number {
    const max = Math.max(...this.holdings().map(x => Math.abs(x.pnl)));
    return max > 0 ? Math.min(100, Math.abs(h.pnl) / max * 100) : 0;
  }

  symColor(sym: string): string {
    const colors = ['#388E3C','#1976D2','#303F9F','#F57C00','#E53935','#7B1FA2','#00796B','#C62828'];
    if (!sym) return colors[0];
    return colors[sym.charCodeAt(0) % colors.length];
  }

  private showToast(msg: string, type: 'success' | 'error') {
    this.toast.set({ msg, type });
    setTimeout(() => this.toast.set(null), 3500);
  }
}
