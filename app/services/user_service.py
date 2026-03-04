"""
User management service for VanTrade.
Handles user creation, lookup, and profile management.
"""

from sqlmodel import Session, select
from app.models.db_models import User
from app.core.database import engine
from app.core.logging import logger
from typing import Optional


class UserService:
    """Service for managing user records."""

    def get_or_create_user(
        self,
        zerodha_user_id: str,
        email: str,
        full_name: str,
    ) -> User:
        """
        Get existing user or create new user record.

        Args:
            zerodha_user_id: User ID from Zerodha OAuth (e.g., "RI2021")
            email: User's email address
            full_name: User's full name

        Returns:
            User object with auto-generated user_id
        """
        with Session(engine) as session:
            # Try to find existing user by zerodha_user_id
            statement = select(User).where(User.zerodha_user_id == zerodha_user_id)
            existing_user = session.exec(statement).first()

            if existing_user:
                logger.info(f"✅ Found existing user: {zerodha_user_id} (ID: {existing_user.user_id})")
                return existing_user

            # Create new user
            new_user = User(
                zerodha_user_id=zerodha_user_id,
                email=email,
                full_name=full_name,
                is_active=True,
            )
            session.add(new_user)
            session.commit()
            session.refresh(new_user)

            logger.info(
                f"✅ Created new user: {zerodha_user_id} (ID: {new_user.user_id}) | "
                f"Email: {email}"
            )
            return new_user

    def get_user_by_zerodha_id(self, zerodha_user_id: str) -> Optional[User]:
        """Get user by Zerodha user ID."""
        with Session(engine) as session:
            statement = select(User).where(User.zerodha_user_id == zerodha_user_id)
            return session.exec(statement).first()

    def get_user_by_id(self, user_id: int) -> Optional[User]:
        """Get user by VanTrade user ID."""
        with Session(engine) as session:
            return session.get(User, user_id)


# Singleton instance
user_service = UserService()
