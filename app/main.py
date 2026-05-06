import asyncio
import uuid as _uuid
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from app.core.config import get_settings
from app.api.routes import agent, performance, auth, analysis, dashboard, credentials, live_trading, backtest, portfolio, ticker, subscription
from app.core.logging import logger

settings = get_settings()

# Shared rate limiter — key by client IP
limiter = Limiter(key_func=get_remote_address, default_limits=["200/minute"])


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.APP_NAME,
        description="Agentic AI Trading System Backend",
        version="2.0.0",
        # Disable /docs and /redoc in production to avoid exposing API schema
        docs_url="/docs" if settings.DEBUG else None,
        redoc_url="/redoc" if settings.DEBUG else None,
    )

    # Rate limiter state
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

    # CORS — restrict to known origins only
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins_list,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "X-Api-Key", "X-Request-ID"],
    )

    # Request correlation ID — stamped on every response so logs can be traced
    @app.middleware("http")
    async def add_correlation_id(request: Request, call_next):
        request_id = request.headers.get("X-Request-ID") or str(_uuid.uuid4())
        request.state.request_id = request_id
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        return response

    # Security headers — added to every response
    @app.middleware("http")
    async def add_security_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
        # HSTS — only set over HTTPS (nginx handles this; here as defence in depth)
        if request.url.scheme == "https":
            response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        return response

    # Routes
    app.include_router(auth.router, prefix="/api/v1/auth", tags=["Authentication"])
    app.include_router(analysis.router, prefix="/api/v1/analysis", tags=["AI Analysis"])
    app.include_router(agent.router, prefix="/api/v1", tags=["Agent"])
    app.include_router(performance.router, prefix="/api/v1", tags=["Performance"])
    app.include_router(dashboard.router, prefix="/api/v1/dashboard", tags=["Dashboard"])
    app.include_router(credentials.router, tags=["Credentials"])
    app.include_router(live_trading.router, prefix="/api/v1", tags=["Live Trading"])
    app.include_router(backtest.router, prefix="/api/v1/backtest", tags=["Backtest"])
    app.include_router(portfolio.router, prefix="/api/v1/portfolio", tags=["Portfolio"])
    app.include_router(ticker.router, prefix="/api/v1/ticker", tags=["Live Ticker"])
    app.include_router(subscription.router, prefix="/api/v1/subscription", tags=["Subscription"])

    @app.on_event("startup")
    async def startup_event():
        logger.info("Application starting up")

        # Start the swing trade expiry scheduler (checks daily at 9:15 AM IST)
        try:
            from app.services.trade_expiry_service import trade_expiry_service
            asyncio.create_task(trade_expiry_service.run_scheduler())
            logger.info("[Startup] Swing trade expiry scheduler started")
        except Exception as e:
            logger.warning(f"[Startup] Could not start expiry scheduler: {e}")

    @app.on_event("shutdown")
    async def shutdown_event():
        logger.info("Application shutting down...")
        try:
            from app.agents.autonomous_agent import autonomous_agent_manager
            await autonomous_agent_manager.stop_all()
            logger.info("✓ All autonomous agents stopped")
        except Exception as e:
            logger.error(f"✗ Error stopping autonomous agents: {str(e)}")

    @app.get("/health")
    async def health_check():
        return {"status": "ok", "app_name": settings.APP_NAME}

    return app

app = create_app()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=settings.DEBUG)
