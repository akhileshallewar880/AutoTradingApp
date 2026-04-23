export interface User {
  userId: string;
  accessToken: string;
  apiKey: string;
  name?: string;
}

export interface IndexPrice {
  symbol: string;
  ltp: number;
  change: number;
  changePct: number;
}

export interface Holding {
  tradingsymbol: string;
  company?: string;
  quantity: number;
  average_price: number;
  last_price: number;
  pnl: number;
  pnl_pct: number;
  day_change?: number;
  day_change_pct?: number;
  invested: number;
  current_value: number;
  stop_loss?: number;
  target?: number;
  max_profit?: number;
  max_loss?: number;
  has_gtt: boolean;
  gtt_id?: string;
}

export interface Position {
  tradingsymbol: string;
  product: string;
  quantity: number;
  average_price: number;
  last_price: number;
  pnl: number;
  realised: number;
  unrealised: number;
}

export interface Gtt {
  id: number;
  tradingsymbol: string;
  type: string;
  status: string;
  trigger_values: number[];
  quantity: number;
  last_price?: number;
}

export interface StockAnalysis {
  stock_symbol: string;
  company_name?: string;
  action: 'BUY' | 'SELL' | 'HOLD';
  entry_price: number;
  stop_loss: number;
  target_price: number;
  quantity: number;
  risk_amount: number;
  potential_profit: number;
  potential_loss: number;
  risk_reward_ratio: number;
  confidence_score: number;
  ai_reasoning: string;
  days_to_target?: number;
  technical_indicators?: Record<string, unknown>;
}

export interface AnalysisResult {
  analysis_id: string;
  status: string;
  stocks: StockAnalysis[];
  portfolio_metrics: {
    total_investment: number;
    total_risk: number;
    max_profit: number;
    max_loss: number;
    available_balance?: number;
  };
  available_balance: number;
  created_at: string;
}

export interface DashboardData {
  total_portfolio_value: number;
  total_invested: number;
  total_pnl: number;
  total_pnl_pct: number;
  day_pnl: number;
  available_balance: number;
  holdings: Holding[];
  positions: Position[];
  gtts: Gtt[];
}
