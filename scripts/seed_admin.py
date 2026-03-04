"""
Admin user seeding script.
Creates the first admin user for the dashboard.

Usage:
    python scripts/seed_admin.py --username admin --email admin@vantrade.io --password secretpassword
"""

import sys
import argparse
from pathlib import Path
from datetime import datetime
from sqlmodel import Session

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.core.database import engine
from app.models.db_models import AdminUser
from sqlalchemy import select, or_
import bcrypt


def hash_password(password: str) -> str:
    """Hash a password using bcrypt."""
    # Convert password to bytes and hash
    salt = bcrypt.gensalt(rounds=12)
    hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
    return hashed.decode('utf-8')


def seed_admin(username: str, email: str, password: str):
    """Create an admin user in the database."""
    try:
        with Session(engine) as session:
            # Check if admin already exists
            statement = select(AdminUser).where(
                or_(AdminUser.username == username, AdminUser.email == email)
            )
            existing = session.exec(statement).first()

            if existing:
                print(f"❌ Admin user already exists:")
                print(f"   Username: {existing.username}")
                print(f"   Email: {existing.email}")
                return False

            # Create new admin
            password_hash = hash_password(password)
            admin_user = AdminUser(
                username=username,
                email=email,
                password_hash=password_hash,
                is_active=True,
                created_at=datetime.utcnow(),
                last_login=None,
            )

            session.add(admin_user)
            session.commit()

            print("✅ Admin user created successfully!")
            print(f"   Username: {username}")
            print(f"   Email: {email}")
            print(f"   Created at: {admin_user.created_at}")
            return True

    except Exception as e:
        print(f"❌ Failed to create admin user: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    parser = argparse.ArgumentParser(description="Seed admin user for VanTrade dashboard")
    parser.add_argument("--username", required=True, help="Admin username")
    parser.add_argument("--email", required=True, help="Admin email")
    parser.add_argument("--password", required=True, help="Admin password")

    args = parser.parse_args()

    print("🔐 Creating admin user...")
    success = seed_admin(args.username, args.email, args.password)

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
