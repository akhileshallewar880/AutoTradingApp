from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import get_settings
from app.api.routes import agent, performance, auth, analysis, dashboard, credentials, live_trading
from app.core.logging import logger

settings = get_settings()

def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.APP_NAME,
        description="Agentic AI Trading System Backend",
        version="1.0.0"
    )

    # CORS
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Routes
    app.include_router(auth.router, prefix="/api/v1/auth", tags=["Authentication"])
    app.include_router(analysis.router, prefix="/api/v1/analysis", tags=["AI Analysis"])
    app.include_router(agent.router, prefix="/api/v1", tags=["Agent"])
    app.include_router(performance.router, prefix="/api/v1", tags=["Performance"])
    app.include_router(dashboard.router, prefix="/api/v1/dashboard", tags=["Dashboard"])
    app.include_router(credentials.router, tags=["Credentials"])
    app.include_router(live_trading.router, prefix="/api/v1", tags=["Live Trading"])

    @app.on_event("startup")
    async def startup_event():
        logger.info("Application starting up (DB-free mode)")

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
