"""
SQLModel database models for VanTrade.
Defines 13 tables with proper relationships, constraints, and indexes.

Tables:
1. User - User accounts and profiles
2. ApiCredential - Encrypted Zerodha API credentials per user
3. Session - User session management
4. Analysis - AI stock analysis requests
5. StockRecommendation - Individual stock recommendations
6. Signal - Technical indicator signals
7. Order - Trade orders placed via Zerodha
8. GttOrder - GTT (Good-Till-Triggered) orders
9. ExecutionUpdate - Real-time order execution updates
10. Trade - Completed trades with P&L
11. OpenPosition - Active positions per user
12. MonthlyPerformance - Aggregated monthly metrics
13. DailyPerformance - Aggregated daily metrics
14. AuditLog - User action audit trail
15. ApiCallLog - API call logging for debugging
16. ErrorLog - Error tracking and analysis
"""

from datetime import datetime, timedelta
from typing import Optional, List
from enum import Enum
from sqlmodel import SQLModel, Field, Relationship, Column, String, Text, JSON
from sqlalchemy import Index, DateTime, func, Numeric, Boolean
from decimal import Decimal


# ============================================================================
# ENUMS - Define constraint values for database columns
# ============================================================================

class OrderStatusEnum(str, Enum):
    """Status of a trade order."""
    PENDING = "PENDING"
    PLACED = "PLACED"
    FILLED = "FILLED"
    PARTIALLY_FILLED = "PARTIALLY_FILLED"
    CANCELLED = "CANCELLED"
    REJECTED = "REJECTED"
    EXPIRED = "EXPIRED"


class GttStatusEnum(str, Enum):
    """Status of a GTT order."""
    ACTIVE = "ACTIVE"
    TRIGGERED = "TRIGGERED"
    CANCELLED = "CANCELLED"
    EXPIRED = "EXPIRED"
    DISABLED = "DISABLED"


class ActionEnum(str, Enum):
    """Trading action: BUY or SELL."""
    BUY = "BUY"
    SELL = "SELL"


class AnalysisStatusEnum(str, Enum):
    """Status of an analysis request."""
    PENDING = "PENDING"
    IN_PROGRESS = "IN_PROGRESS"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"
    CANCELLED = "CANCELLED"


class ProductTypeEnum(str, Enum):
    """Zerodha product types."""
    MIS = "MIS"  # Margin Intraday Square-off
    CNC = "CNC"  # Cash and Carry


class TradeStatusEnum(str, Enum):
    """Status of a completed trade."""
    OPEN = "OPEN"
    CLOSED = "CLOSED"
    PARTIAL_EXIT = "PARTIAL_EXIT"


class UpdateTypeEnum(str, Enum):
    """Type of execution update."""
    ORDER_PLACED = "ORDER_PLACED"
    ORDER_FILLED = "ORDER_FILLED"
    GTT_TRIGGERED = "GTT_TRIGGERED"
    GTT_CANCELLED = "GTT_CANCELLED"
    PARTIAL_FILL = "PARTIAL_FILL"
    REJECTED = "REJECTED"
    ERROR = "ERROR"


class SeverityEnum(str, Enum):
    """Error severity levels."""
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"


# ============================================================================
# MAIN TABLES - Core domain models
# ============================================================================

class User(SQLModel, table=True):
    """
    User account information.
    Stores basic profile and authentication data.
    """
    __tablename__ = "vantrade_users"

    user_id: Optional[int] = Field(default=None, primary_key=True, index=True)
    zerodha_user_id: str = Field(index=True, unique=True, max_length=255)  # Zerodha's user_id from OAuth
    email: str = Field(index=True, unique=True, max_length=255)
    full_name: str = Field(max_length=255)
    is_active: bool = Field(default=True)
    user_type: str = Field(default="USER", max_length=10)  # USER or ADMIN
    created_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )
    updated_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    )

    # Relationships
    api_credentials: List["ApiCredential"] = Relationship(back_populates="user", cascade_delete=True)
    sessions: List["Session"] = Relationship(back_populates="user", cascade_delete=True)
    analyses: List["Analysis"] = Relationship(back_populates="user", cascade_delete=True)
    orders: List["Order"] = Relationship(back_populates="user", cascade_delete=True)
    gtt_orders: List["GttOrder"] = Relationship(back_populates="user", cascade_delete=True)
    trades: List["Trade"] = Relationship(back_populates="user", cascade_delete=True)
    open_positions: List["OpenPosition"] = Relationship(back_populates="user", cascade_delete=True)
    monthly_performances: List["MonthlyPerformance"] = Relationship(back_populates="user", cascade_delete=True)
    daily_performances: List["DailyPerformance"] = Relationship(back_populates="user", cascade_delete=True)
    token_usages: List["TokenUsage"] = Relationship(back_populates="user", cascade_delete=True)
    audit_logs: List["AuditLog"] = Relationship(back_populates="user", cascade_delete=True)
    api_call_logs: List["ApiCallLog"] = Relationship(back_populates="user", cascade_delete=True)
    error_logs: List["ErrorLog"] = Relationship(back_populates="user", cascade_delete=True)


class ApiCredential(SQLModel, table=True):
    """
    Encrypted Zerodha API credentials per user.
    Stores user's personal Zerodha API key and secret (encrypted).
    """
    __tablename__ = "vantrade_api_credentials"

    credential_id: Optional[int] = Field(default=None, primary_key=True, index=True)
    user_id: int = Field(foreign_key="vantrade_users.user_id", index=True)
    api_key_encrypted: str  # Fernet-encrypted Zerodha API key
    api_secret_encrypted: str  # Fernet-encrypted Zerodha API secret
    access_token_encrypted: Optional[str] = None  # Fernet-encrypted Zerodha access token
    is_valid: bool = Field(default=True)
    expires_at: Optional[datetime] = None
    created_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )
    updated_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    )

    # Relationships
    user: User = Relationship(back_populates="api_credentials")


class Session(SQLModel, table=True):
    """
    User session management.
    Tracks active user sessions for authentication.
    """
    __tablename__ = "vantrade_sessions"

    session_id: Optional[int] = Field(default=None, primary_key=True, index=True)
    user_id: int = Field(foreign_key="vantrade_users.user_id", index=True)
    access_token: str
    ip_address: str
    is_active: bool = Field(default=True)
    last_activity: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )
    created_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )

    # Relationships
    user: User = Relationship(back_populates="sessions")


class Analysis(SQLModel, table=True):
    """
    AI stock analysis request.
    Records each analysis execution with status and overall metrics.
    """
    __tablename__ = "vantrade_analyses"

    analysis_id: Optional[str] = Field(default=None, primary_key=True, index=True)  # UUID string
    user_id: Optional[int] = Field(None, foreign_key="vantrade_users.user_id", index=True)  # Optional, analyses can exist without users
    status: AnalysisStatusEnum = Field(default=AnalysisStatusEnum.PENDING)
    hold_duration_days: int  # 0 = Intraday, >0 = Swing
    total_investment: Decimal = Field(sa_column=Column(Numeric(12, 2)))
    max_profit: Optional[Decimal] = Field(None, sa_column=Column(Numeric(12, 2)))
    max_loss: Optional[Decimal] = Field(None, sa_column=Column(Numeric(12, 2)))
    created_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )
    completed_at: Optional[datetime] = None

    # Relationships
    user: User = Relationship(back_populates="analyses")
    recommendations: List["StockRecommendation"] = Relationship(back_populates="analysis", cascade_delete=True)
    orders: List["Order"] = Relationship(back_populates="analysis", cascade_delete=True)
    execution_updates: List["ExecutionUpdate"] = Relationship(back_populates="analysis", cascade_delete=True)

    # Indexes
    __table_args__ = (
        Index("idx_analysis_user_created", "user_id", "created_at"),
        Index("idx_analysis_status", "status"),
    )


class StockRecommendation(SQLModel, table=True):
    """
    Individual stock recommendation within an analysis.
    Contains entry, stop-loss, and target prices.
    """
    __tablename__ = "vantrade_stock_recommendations"

    recommendation_id: Optional[int] = Field(default=None, primary_key=True, index=True)
    analysis_id: str = Field(foreign_key="vantrade_analyses.analysis_id", index=True)
    stock_symbol: str = Field(index=True, max_length=20)
    action: ActionEnum  # BUY or SELL
    entry_price: Decimal = Field(sa_column=Column(Numeric(10, 2)))
    stop_loss: Decimal = Field(sa_column=Column(Numeric(10, 2)))
    target_price: Decimal = Field(sa_column=Column(Numeric(10, 2)))
    quantity: int = Field(default=1)
    confidence_score: Decimal = Field(sa_column=Column(Numeric(5, 2)))  # 0-100
    rationale: Optional[str] = Field(None, sa_column=Column(Text))
    created_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )

    # Relationships
    analysis: Analysis = Relationship(back_populates="recommendations")
    signals: List["Signal"] = Relationship(back_populates="recommendation", cascade_delete=True)

    # Indexes
    __table_args__ = (
        Index("idx_recommendation_analysis", "analysis_id"),
        Index("idx_recommendation_symbol", "stock_symbol"),
    )


class Signal(SQLModel, table=True):
    """
    Technical indicator signals for a recommendation.
    Stores individual indicator values that led to BUY/SELL signal.
    """
    __tablename__ = "vantrade_signals"

    signal_id: Optional[int] = Field(default=None, primary_key=True, index=True)
    recommendation_id: int = Field(foreign_key="vantrade_stock_recommendations.recommendation_id", index=True)
    signal_type: str  # E.g., "VWAP_RSI", "MACD_RSI", "BB_RSI"
    signal_value: str  # E.g., "BUY", "SELL"
    indicator_values: dict = Field(sa_column=Column(JSON))  # {"RSI": 45, "VWAP": 120.5, ...}
    created_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )

    # Relationships
    recommendation: StockRecommendation = Relationship(back_populates="signals")


class Order(SQLModel, table=True):
    """
    Trade order placed via Zerodha.
    Records entry order for a stock recommendation.
    """
    __tablename__ = "vantrade_orders"

    order_id: Optional[int] = Field(default=None, primary_key=True, index=True)
    user_id: int = Field(foreign_key="vantrade_users.user_id", index=True)
    analysis_id: str = Field(foreign_key="vantrade_analyses.analysis_id", index=True)
    stock_symbol: str = Field(index=True, max_length=20)
    action: ActionEnum  # BUY or SELL
    quantity: int
    order_type: str  # "MARKET", "LIMIT", "STOP_LOSS", etc.
    order_status: OrderStatusEnum = Field(default=OrderStatusEnum.PENDING)
    entry_price: Optional[Decimal] = Field(None, sa_column=Column(Numeric(10, 2)))
    fill_price: Optional[Decimal] = Field(None, sa_column=Column(Numeric(10, 2)))
    zerodha_order_id: Optional[str] = Field(None, index=True, max_length=255)
    product_type: ProductTypeEnum  # MIS or CNC
    created_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )
    filled_at: Optional[datetime] = None

    # Relationships
    user: User = Relationship(back_populates="orders")
    analysis: Analysis = Relationship(back_populates="orders")
    gtt_orders: List["GttOrder"] = Relationship(back_populates="order", cascade_delete=True)
    trade: Optional["Trade"] = Relationship(back_populates="entry_order")

    # Indexes
    __table_args__ = (
        Index("idx_order_user_created", "user_id", "created_at"),
        Index("idx_order_analysis", "analysis_id"),
        Index("idx_order_symbol", "stock_symbol"),
    )


class GttOrder(SQLModel, table=True):
    """
    GTT (Good-Till-Triggered) exit orders.
    Stores automated stop-loss and target exit orders.
    """
    __tablename__ = "vantrade_gtt_orders"

    gtt_id: Optional[int] = Field(default=None, primary_key=True, index=True)
    user_id: int = Field(foreign_key="vantrade_users.user_id", index=True)
    order_id: int = Field(foreign_key="vantrade_orders.order_id", index=True)
    zerodha_gtt_id: Optional[str] = Field(None, index=True, max_length=255)
    target_price: Decimal = Field(sa_column=Column(Numeric(10, 2)))
    stop_loss: Decimal = Field(sa_column=Column(Numeric(10, 2)))
    gtt_status: GttStatusEnum = Field(default=GttStatusEnum.ACTIVE)
    created_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )
    triggered_at: Optional[datetime] = None

    # Relationships
    user: User = Relationship(back_populates="gtt_orders")
    order: Order = Relationship(back_populates="gtt_orders")

    # Indexes
    __table_args__ = (
        Index("idx_gtt_user", "user_id"),
        Index("idx_gtt_status", "gtt_status"),
    )


class ExecutionUpdate(SQLModel, table=True):
    """
    Real-time order execution updates.
    Logs each stage of order execution (placed, filled, GTT triggered, etc.).
    """
    __tablename__ = "vantrade_execution_updates"

    update_id: Optional[int] = Field(default=None, primary_key=True, index=True)
    analysis_id: str = Field(foreign_key="vantrade_analyses.analysis_id", index=True)
    stock_symbol: str = Field(index=True, max_length=20)
    update_type: str  # Free-form string (ORDER_PLACING, ORDER_PLACED, GTT_PLACED, COMPLETED, ERROR, etc.)
    message: Optional[str] = Field(None, sa_column=Column(Text))
    order_id: Optional[str] = Field(None, max_length=255)
    status: Optional[str] = Field(None, max_length=50)
    timestamp: Optional[datetime] = None
    created_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )

    # Relationships
    analysis: Analysis = Relationship(back_populates="execution_updates")

    # Indexes
    __table_args__ = (
        Index("idx_execution_analysis", "analysis_id"),
        Index("idx_execution_symbol", "stock_symbol"),
    )


class Trade(SQLModel, table=True):
    """
    Completed trade with P&L calculation.
    Records closed positions with profit/loss.
    """
    __tablename__ = "vantrade_trades"

    trade_id: Optional[int] = Field(default=None, primary_key=True, index=True)
    user_id: int = Field(foreign_key="vantrade_users.user_id", index=True)
    entry_order_id: int = Field(foreign_key="vantrade_orders.order_id", index=True)
    stock_symbol: str = Field(index=True, max_length=20)
    entry_price: Decimal = Field(sa_column=Column(Numeric(10, 2)))
    exit_price: Optional[Decimal] = Field(None, sa_column=Column(Numeric(10, 2)))
    quantity: int
    trade_status: TradeStatusEnum = Field(default=TradeStatusEnum.OPEN)
    pnl: Optional[Decimal] = Field(None, sa_column=Column(Numeric(12, 2)))  # Profit/Loss in rupees
    pnl_percent: Optional[Decimal] = Field(None, sa_column=Column(Numeric(6, 2)))  # Profit/Loss percentage
    entry_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )
    exit_at: Optional[datetime] = None

    # Relationships
    user: User = Relationship(back_populates="trades")
    entry_order: Order = Relationship(back_populates="trade")

    # Indexes
    __table_args__ = (
        Index("idx_trade_user_entry", "user_id", "entry_at"),
        Index("idx_trade_symbol", "stock_symbol"),
    )


class OpenPosition(SQLModel, table=True):
    """
    Active open positions per user.
    Tracks unrealized P&L for open trades.
    """
    __tablename__ = "vantrade_open_positions"

    position_id: Optional[int] = Field(default=None, primary_key=True, index=True)
    user_id: int = Field(foreign_key="vantrade_users.user_id", index=True)
    trade_id: int = Field(foreign_key="vantrade_trades.trade_id", index=True)
    stock_symbol: str = Field(index=True, max_length=20)
    quantity: int
    entry_price: Decimal = Field(sa_column=Column(Numeric(10, 2)))
    current_price: Decimal = Field(sa_column=Column(Numeric(10, 2)))
    unrealized_pnl: Decimal = Field(sa_column=Column(Numeric(12, 2)))
    unrealized_pnl_percent: Decimal = Field(sa_column=Column(Numeric(6, 2)))
    updated_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    )

    # Relationships
    user: User = Relationship(back_populates="open_positions")
    trade: Trade = Relationship()


class MonthlyPerformance(SQLModel, table=True):
    """
    Monthly aggregated performance metrics.
    Computed from all trades in a month.
    """
    __tablename__ = "vantrade_monthly_performances"

    performance_id: Optional[int] = Field(default=None, primary_key=True, index=True)
    user_id: int = Field(foreign_key="vantrade_users.user_id", index=True)
    year: int = Field(index=True)
    month: int = Field(index=True)
    total_trades: int
    winning_trades: int
    losing_trades: int
    win_rate: Decimal = Field(sa_column=Column(Numeric(5, 2)))  # Percentage
    total_pnl: Decimal = Field(sa_column=Column(Numeric(12, 2)))
    avg_win: Decimal = Field(sa_column=Column(Numeric(12, 2)))
    avg_loss: Decimal = Field(sa_column=Column(Numeric(12, 2)))
    profit_factor: Decimal = Field(sa_column=Column(Numeric(5, 2)))
    max_drawdown: Decimal = Field(sa_column=Column(Numeric(6, 2)))
    created_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )

    # Relationships
    user: User = Relationship(back_populates="monthly_performances")

    # Indexes
    __table_args__ = (
        Index("idx_monthly_perf_user_date", "user_id", "year", "month"),
    )


class DailyPerformance(SQLModel, table=True):
    """
    Daily aggregated performance metrics.
    Computed from all trades in a day.
    """
    __tablename__ = "vantrade_daily_performances"

    performance_id: Optional[int] = Field(default=None, primary_key=True, index=True)
    user_id: int = Field(foreign_key="vantrade_users.user_id", index=True)
    performance_date: str = Field(index=True, max_length=10)  # YYYY-MM-DD
    total_trades: int
    winning_trades: int
    losing_trades: int
    total_pnl: Decimal = Field(sa_column=Column(Numeric(12, 2)))
    best_trade: Decimal = Field(sa_column=Column(Numeric(12, 2)))
    worst_trade: Decimal = Field(sa_column=Column(Numeric(12, 2)))
    created_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )

    # Relationships
    user: User = Relationship(back_populates="daily_performances")

    # Indexes
    __table_args__ = (
        Index("idx_daily_perf_user_date", "user_id", "performance_date"),
    )


# ============================================================================
# TOKEN USAGE & ADMIN TABLES - Token tracking and admin management
# ============================================================================

class TokenUsage(SQLModel, table=True):
    """
    OpenAI token usage tracking per analysis.
    Records prompt tokens, completion tokens, and estimated cost.
    """
    __tablename__ = "vantrade_token_usage"

    id: Optional[int] = Field(default=None, primary_key=True, index=True)
    user_id: Optional[int] = Field(None, foreign_key="vantrade_users.user_id", index=True)
    analysis_id: Optional[str] = None  # Analysis ID that consumed these tokens
    model: str = Field(default="gpt-4o", max_length=50)
    prompt_tokens: int = Field(default=0)
    completion_tokens: int = Field(default=0)
    total_tokens: int = Field(default=0)
    estimated_cost_usd: Decimal = Field(default=Decimal("0"), sa_column=Column(Numeric(10, 6)))
    created_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )

    # Relationships
    user: Optional[User] = Relationship(back_populates="token_usages")

    # Indexes
    __table_args__ = (
        Index("idx_token_user_created", "user_id", "created_at"),
        Index("idx_token_created", "created_at"),
    )


class AdminUser(SQLModel, table=True):
    """
    Admin user accounts for dashboard access.
    Stores username, email, and hashed password for admin authentication.
    """
    __tablename__ = "vantrade_admin_users"

    id: Optional[int] = Field(default=None, primary_key=True, index=True)
    username: str = Field(unique=True, max_length=50)
    email: str = Field(unique=True, max_length=255)
    password_hash: str  # bcrypt hashed password
    is_active: bool = Field(default=True)
    created_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )
    last_login: Optional[datetime] = None


# ============================================================================
# AUDIT & LOGGING TABLES - Compliance and debugging
# ============================================================================

class AuditLog(SQLModel, table=True):
    """
    Complete audit trail of user actions.
    Records every significant user action for compliance.
    """
    __tablename__ = "vantrade_audit_logs"

    audit_id: Optional[int] = Field(default=None, primary_key=True, index=True)
    user_id: int = Field(foreign_key="vantrade_users.user_id", index=True)
    action: str = Field(max_length=255)  # E.g., "LOGIN", "ANALYSIS_CREATED", "ORDER_PLACED"
    resource_type: Optional[str] = None  # E.g., "Analysis", "Order"
    resource_id: Optional[str] = None  # ID of the affected resource
    request_body: Optional[dict] = Field(None, sa_column=Column(JSON))
    response_body: Optional[dict] = Field(None, sa_column=Column(JSON))
    ip_address: str
    user_agent: Optional[str] = None
    created_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )

    # Relationships
    user: User = Relationship(back_populates="audit_logs")

    # Indexes
    __table_args__ = (
        Index("idx_audit_user_created", "user_id", "created_at"),
        Index("idx_audit_action", "action"),
    )


class ApiCallLog(SQLModel, table=True):
    """
    API call logging for debugging and monitoring.
    Tracks all API calls made by the system.
    """
    __tablename__ = "vantrade_api_call_logs"

    log_id: Optional[int] = Field(default=None, primary_key=True, index=True)
    user_id: int = Field(foreign_key="vantrade_users.user_id", index=True)
    endpoint: str = Field(max_length=255)
    method: str = Field(max_length=10)  # GET, POST, PUT, DELETE
    request_params: Optional[dict] = Field(None, sa_column=Column(JSON))
    response_status: int
    response_data: Optional[dict] = Field(None, sa_column=Column(JSON))
    response_time_ms: int
    error_message: Optional[str] = None
    created_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )

    # Relationships
    user: User = Relationship(back_populates="api_call_logs")

    # Indexes
    __table_args__ = (
        Index("idx_api_call_user_created", "user_id", "created_at"),
        Index("idx_api_call_endpoint", "endpoint"),
    )


class ErrorLog(SQLModel, table=True):
    """
    Error tracking and analysis.
    Logs all errors for debugging and monitoring.
    """
    __tablename__ = "vantrade_error_logs"

    error_id: Optional[int] = Field(default=None, primary_key=True, index=True)
    user_id: Optional[int] = Field(None, foreign_key="vantrade_users.user_id", index=True)  # Optional for system errors
    error_type: str  # E.g., "ConnectionError", "ValidationError"
    error_message: str = Field(sa_column=Column(Text))
    stack_trace: Optional[str] = Field(None, sa_column=Column(Text))
    context_data: Optional[dict] = Field(None, sa_column=Column(JSON))
    severity: SeverityEnum = Field(default=SeverityEnum.ERROR)
    is_resolved: bool = Field(default=False)
    created_at: datetime = Field(
        default_factory=datetime.utcnow,
        sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )

    # Relationships
    user: Optional[User] = Relationship(back_populates="error_logs")

    # Indexes
    __table_args__ = (
        Index("idx_error_created", "created_at"),
        Index("idx_error_severity", "severity"),
        Index("idx_error_resolved", "is_resolved"),
    )
