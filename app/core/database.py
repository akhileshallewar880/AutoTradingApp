"""
Database connection, engine, and session management for SQLModel.
Supports Azure SQL Server with connection pooling and automatic table creation.
"""

from sqlalchemy import create_engine, event, Engine
from sqlalchemy.pool import QueuePool
from sqlmodel import SQLModel, Session
from typing import Generator
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
    # Extract server name without domain for @servername suffix
    server_name = settings.DB_SERVER.split('.')[0]  # e.g., "vanyatradbserver"

    # Format: Driver={driver};Server=server;Database=db;UID=user@server;PWD=password;
    connection_string = (
        f"mssql+pyodbc:///?odbc_connect="
        f"Driver={{{settings.DB_DRIVER}}};"
        f"Server={settings.DB_SERVER};"
        f"Database={settings.DB_NAME};"
        f"UID={settings.DB_USER}@{server_name};"
        f"PWD={settings.DB_PASSWORD};"
        f"Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
    )
    return connection_string

# Create SQLModel engine with connection pooling
engine = create_engine(
    get_database_url(),
    echo=settings.DEBUG,  # Log SQL queries if DEBUG is True
    poolclass=QueuePool,
    pool_size=settings.DB_POOL_SIZE,
    max_overflow=settings.DB_MAX_OVERFLOW,
    pool_recycle=3600,  # Recycle connections after 1 hour
    pool_pre_ping=True,  # Test connection before using from pool
)

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

    Example:
        from fastapi import Depends

        @app.get("/users")
        async def get_users(session: Session = Depends(get_session)):
            users = session.query(User).all()
            return users
    """
    with Session(engine) as session:
        yield session


def init_db() -> None:
    """
    Initialize database by creating all tables defined in SQLModel models.
    Call this on application startup.

    This function:
    1. Imports all model definitions (triggers metadata registration)
    2. Creates VanTrade-specific tables (only if they don't already exist)
    3. Does NOT drop or modify tables from other apps using the same database
    4. Logs success/failure

    Note: Requires all models to be imported before calling this function.
    Models are imported in __init__.py files.
    """
    try:
        # Import all models to register them with SQLModel metadata
        # This must be done before create_all()
        from app.models.db_models import (
            User, ApiCredential, Session as DbSession,
            Analysis, StockRecommendation, Signal,
            Order, GttOrder, ExecutionUpdate,
            Trade, OpenPosition,
            MonthlyPerformance, DailyPerformance,
            AuditLog, ApiCallLog, ErrorLog
        )

        # Create tables only if they don't exist (checkfirst=True)
        # This preserves other apps' tables in the same database
        logger.info("Creating VanTrade tables (if they don't exist)...")
        SQLModel.metadata.create_all(engine, checkfirst=True)
        logger.info("✓ Database initialized successfully - VanTrade tables created/verified")

    except Exception as e:
        logger.error(f"✗ Database initialization failed: {str(e)}")
        raise


def close_db() -> None:
    """
    Close database connections on application shutdown.
    Call this on application shutdown.
    """
    try:
        engine.dispose()
        logger.info("✓ Database connections closed")
    except Exception as e:
        logger.error(f"✗ Error closing database connections: {str(e)}")
        raise
