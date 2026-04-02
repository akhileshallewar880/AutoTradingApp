"""
Database connection, engine, and session management for SQLModel.
Supports Azure SQL Server with connection pooling and automatic table creation.
"""

from sqlalchemy import create_engine, event, Engine
from sqlalchemy.pool import QueuePool
from sqlmodel import SQLModel, Session
from typing import Generator, Optional
from app.core.config import get_settings
from app.core.logging import logger

settings = get_settings()

# Build Azure SQL connection string
def get_database_url() -> str:
    """
    Construct MSSQL connection string for Azure SQL.
    Uses pyodbc DSN connection format which handles special characters better.
    For Azure SQL, username must include @servername suffix.
    """
    if not settings.DB_SERVER:
        raise RuntimeError("DB_SERVER is not configured. Set the DB_SERVER environment variable.")

    is_local = settings.DB_SERVER.lower() in ("localhost", "127.0.0.1", "::1")

    # Local SQL Server uses self-signed cert — trust it automatically
    # Azure SQL uses a valid cert — verify it
    trust_cert = "yes" if is_local else "no"
    encrypt = "yes"

    # Azure SQL requires @servername suffix in UID; local SA login does not
    uid = settings.DB_USER if is_local else f"{settings.DB_USER}@{settings.DB_SERVER.split('.')[0]}"

    connection_string = (
        f"mssql+pyodbc:///?odbc_connect="
        f"Driver={{{settings.DB_DRIVER}}};"
        f"Server={settings.DB_SERVER};"
        f"Database={settings.DB_NAME};"
        f"UID={uid};"
        f"PWD={settings.DB_PASSWORD};"
        f"Encrypt={encrypt};TrustServerCertificate={trust_cert};Connection Timeout=30;"
    )
    return connection_string


def _create_engine():
    if not settings.DB_SERVER:
        return None
    return create_engine(
        get_database_url(),
        echo=settings.DEBUG,
        poolclass=QueuePool,
        pool_size=settings.DB_POOL_SIZE,
        max_overflow=settings.DB_MAX_OVERFLOW,
        pool_recycle=3600,
        pool_pre_ping=True,
    )

# Create SQLModel engine with connection pooling (None when DB not configured)
engine = _create_engine()

@event.listens_for(Engine, "connect")
def receive_connect(dbapi_conn, connection_record):
    """Enable row-level security and other SQL Server features on each connection."""
    cursor = dbapi_conn.cursor()
    cursor.execute("SET ANSI_NULLS ON")
    cursor.execute("SET QUOTED_IDENTIFIER ON")
    cursor.close()


def get_session() -> Generator[Session, None, None]:
    """
    FastAPI dependency for database sessions.
    Yields a SQLModel Session that is automatically closed after use.
    """
    if engine is None:
        raise RuntimeError("Database is not configured.")
    with Session(engine) as session:
        yield session


def init_db() -> None:
    """
    Initialize database by creating all tables defined in SQLModel models.
    Call this on application startup.
    """
    if engine is None:
        logger.warning("Skipping DB init — DB_SERVER not configured.")
        return
    try:
        from app.models.db_models import (
            User, ApiCredential, Session as DbSession,
            Analysis, StockRecommendation, Signal,
            Order, GttOrder, ExecutionUpdate,
            Trade, OpenPosition,
            MonthlyPerformance, DailyPerformance, DailyPnlRecord,
            AuditLog, ApiCallLog, ErrorLog
        )

        logger.info("Creating VanTrade tables (if they don't exist)...")
        SQLModel.metadata.create_all(engine, checkfirst=True)
        logger.info("✓ Database initialized successfully - VanTrade tables created/verified")

    except Exception as e:
        logger.error(f"✗ Database initialization failed: {str(e)}")
        raise


def close_db() -> None:
    """
    Close database connections on application shutdown.
    """
    if engine is None:
        return
    try:
        engine.dispose()
        logger.info("✓ Database connections closed")
    except Exception as e:
        logger.error(f"✗ Error closing database connections: {str(e)}")
        raise
