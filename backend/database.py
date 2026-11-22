"""
TransitIQ Backend - Database Connection & Query Utilities
Provides thread-safe connection pooling, transaction managers, and query executors.
"""

import logging
import psycopg2
from psycopg2.pool import ThreadedConnectionPool
from psycopg2.extras import RealDictCursor
from contextlib import contextmanager
from typing import List, Dict, Any, Optional, Tuple
from decimal import Decimal
from datetime import date, time, datetime

from .config import settings

logger = logging.getLogger("transitiq.database")

_pool: Optional[ThreadedConnectionPool] = None


def init_db_pool():
    """Initializes the PostgreSQL connection pool."""
    global _pool
    if _pool is None:
        try:
            _pool = ThreadedConnectionPool(
                minconn=settings.DB_MIN_CONN,
                maxconn=settings.DB_MAX_CONN,
                host=settings.DB_HOST,
                port=settings.DB_PORT,
                database=settings.DB_NAME,
                user=settings.DB_USER,
                password=settings.DB_PASSWORD,
                cursor_factory=RealDictCursor,
                connect_timeout=5
            )
            logger.info("PostgreSQL connection pool initialized successfully.")
        except Exception as e:
            logger.error(f"Failed to initialize connection pool: {e}")
            raise


def close_db_pool():
    """Closes all connections in the pool on shutdown."""
    global _pool
    if _pool is not None:
        _pool.closeall()
        _pool = None
        logger.info("PostgreSQL connection pool closed.")


@contextmanager
def get_db_connection():
    """Context manager for acquiring and releasing a connection from the pool."""
    global _pool
    if _pool is None:
        init_db_pool()

    conn = _pool.getconn()
    try:
        yield conn
    finally:
        _pool.putconn(conn)


@contextmanager
def get_db_cursor(commit: bool = False):
    """
    Context manager yielding a database cursor.
    Optionally commits the transaction upon successful exit.
    """
    with get_db_connection() as conn:
        cursor = conn.cursor()
        try:
            yield cursor
            if commit:
                conn.commit()
        except Exception as e:
            conn.rollback()
            logger.error(f"Database error rolled back: {e}")
            raise
        finally:
            cursor.close()


def sanitize_row(row: Dict[str, Any]) -> Dict[str, Any]:
    """Converts Decimals, dates, and times into JSON-serializable types."""
    if not row:
        return row
    clean = {}
    for k, v in row.items():
        if isinstance(v, Decimal):
            clean[k] = float(v)
        elif isinstance(v, (datetime, date, time)):
            clean[k] = v.isoformat()
        else:
            clean[k] = v
    return clean


def fetch_all(query: str, params: Optional[Tuple] = None) -> List[Dict[str, Any]]:
    """Executes a query and returns all matching rows as dictionaries."""
    with get_db_cursor(commit=False) as cur:
        cur.execute(query, params)
        rows = cur.fetchall()
        return [sanitize_row(dict(r)) for r in rows]


def fetch_one(query: str, params: Optional[Tuple] = None) -> Optional[Dict[str, Any]]:
    """Executes a query and returns a single row dictionary or None."""
    with get_db_cursor(commit=False) as cur:
        cur.execute(query, params)
        row = cur.fetchone()
        return sanitize_row(dict(row)) if row else None


def execute_dml(query: str, params: Optional[Tuple] = None) -> int:
    """Executes an INSERT, UPDATE, or DELETE query and returns the affected row count."""
    with get_db_cursor(commit=True) as cur:
        cur.execute(query, params)
        return cur.rowcount


def execute_returning(query: str, params: Optional[Tuple] = None) -> Optional[Dict[str, Any]]:
    """Executes an INSERT/UPDATE query with a RETURNING clause."""
    with get_db_cursor(commit=True) as cur:
        cur.execute(query, params)
        row = cur.fetchone()
        return sanitize_row(dict(row)) if row else None
