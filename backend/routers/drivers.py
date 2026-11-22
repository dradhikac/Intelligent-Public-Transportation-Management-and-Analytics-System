"""
TransitIQ API - Driver Roster & Performance Router
Manages drivers, license compliance audits, and driver performance scoring.
"""

from fastapi import APIRouter, HTTPException
from typing import Optional
from ..database import fetch_all, fetch_one

router = APIRouter(prefix="/api/drivers", tags=["Driver Personnel & Compliance"])


@router.get("")
def get_drivers(status: Optional[str] = None):
    """Retrieves all drivers with license expiry and operational duty status."""
    query = """
        SELECT
            driver_id,
            employee_code,
            first_name,
            last_name,
            first_name || ' ' || COALESCE(last_name, '') AS full_name,
            phone_number,
            license_number,
            license_expiry_date,
            date_of_joining,
            status,
            CASE
                WHEN license_expiry_date < CURRENT_DATE THEN 'EXPIRED'
                WHEN license_expiry_date <= CURRENT_DATE + INTERVAL '30 days' THEN 'EXPIRING_SOON'
                ELSE 'VALID'
            END AS license_status,
            (license_expiry_date - CURRENT_DATE) AS days_until_license_expiry
        FROM drivers
        WHERE 1=1
    """
    params = []
    if status:
        query += " AND status = %s"
        params.append(status.upper())
    query += " ORDER BY driver_id ASC;"
    return fetch_all(query, tuple(params))


@router.get("/{driver_id}/license-audit")
def audit_driver_license(driver_id: int):
    """Executes PL/pgSQL function fn_check_license_expiry(driver_id)."""
    query = "SELECT * FROM fn_check_license_expiry(%s);"
    try:
        res = fetch_one(query, (driver_id,))
        if not res:
            raise HTTPException(status_code=404, detail="Driver not found")
        return res
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/{driver_id}/performance-function")
def get_driver_performance_function(driver_id: int):
    """Executes PL/pgSQL function fn_get_driver_performance(driver_id)."""
    query = "SELECT * FROM fn_get_driver_performance(%s);"
    try:
        res = fetch_one(query, (driver_id,))
        if not res:
            raise HTTPException(status_code=404, detail="Driver performance metrics not found")
        return res
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/views/performance")
def get_driver_performance_view():
    """Queries production view vw_driver_performance."""
    query = "SELECT * FROM vw_driver_performance ORDER BY total_assigned_trips DESC;"
    return fetch_all(query)
