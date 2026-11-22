"""
TransitIQ API - System Health & Diagnostics Router
Exposes PostgreSQL database connection health, engine version, and connection pool status.
"""

from fastapi import APIRouter
from ..database import fetch_one
from ..config import settings

router = APIRouter(prefix="/api/system", tags=["System Health & Diagnostics"])


@router.get("/health")
def get_system_health():
    """Checks PostgreSQL engine connectivity and reports version and database state."""
    try:
        db_info = fetch_one("""
            SELECT
                version() AS postgresql_version,
                current_database() AS database_name,
                current_user AS connected_user,
                inet_server_addr() AS server_address,
                inet_server_port() AS server_port,
                pg_is_in_recovery() AS is_in_recovery;
        """)

        tables_count = fetch_one("""
            SELECT COUNT(*) AS total_tables
            FROM information_schema.tables
            WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
        """)

        return {
            "status": "HEALTHY",
            "service": settings.APP_NAME,
            "version": settings.APP_VERSION,
            "database": {
                "name": settings.DB_NAME,
                "host": settings.DB_HOST,
                "port": settings.DB_PORT,
                "tables_count": tables_count["total_tables"] if tables_count else 0,
                "engine": db_info["postgresql_version"] if db_info else "Unknown"
            }
        }
    except Exception as e:
        return {
            "status": "DEGRADED",
            "error": str(e),
            "service": settings.APP_NAME,
            "version": settings.APP_VERSION
        }
