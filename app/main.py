from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import get_settings
from app.api.routes import agent, performance, auth, analysis, dashboard
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

    @app.on_event("startup")
    async def startup_event():
        logger.info("Application starting up...")

    @app.get("/health")
    async def health_check():
        return {"status": "ok", "app_name": settings.APP_NAME}

    return app

app = create_app()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=settings.DEBUG)
