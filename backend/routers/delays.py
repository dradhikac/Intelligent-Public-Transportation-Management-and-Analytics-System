"""
TransitIQ API - Delay & Incident Management Router
Manages service delays, root causes, automatic severity classification, and sp_record_delay.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from typing import Optional
from ..database import fetch_all, fetch_one, get_db_cursor

router = APIRouter(prefix="/api/delays", tags=["Delay & Incident Management"])


class DelayRecordCreate(BaseModel):
    trip_stop_log_id: int
    reason_id: int
    delay_seconds: int = Field(..., ge=0)
    remarks: Optional[str] = None


@router.get("/analysis")
def get_delay_analysis():
    """Queries production view vw_delay_analysis."""
    query = "SELECT * FROM vw_delay_analysis ORDER BY delay_seconds DESC;"
    return fetch_all(query)


@router.get("/reasons")
def get_delay_reasons():
    """Retrieves all defined delay reason categories."""
    query = "SELECT * FROM delay_reasons ORDER BY reason_id ASC;"
    return fetch_all(query)


@router.post("/record")
def record_delay(payload: DelayRecordCreate):
    """
    Logs a delay incident using stored procedure sp_record_delay.
    PostgreSQL trigger trg_auto_classify_delay automatically assigns
    severity based on delay_seconds (MINOR, MODERATE, SEVERE).
    """
    try:
        with get_db_cursor(commit=True) as cur:
            cur.execute("""
                CALL sp_record_delay(%s, %s, %s, %s, NULL);
            """, (
                payload.trip_stop_log_id,
                payload.reason_id,
                payload.delay_seconds,
                payload.remarks
            ))

        # Retrieve created record
        latest = fetch_one("""
            SELECT
                d.delay_id,
                d.trip_stop_log_id,
                dr.reason_name,
                d.delay_seconds,
                d.severity,
                d.remarks,
                d.recorded_at
            FROM delay_records d
            JOIN delay_reasons dr ON d.reason_id = dr.reason_id
            WHERE d.trip_stop_log_id = %s
            ORDER BY d.delay_id DESC LIMIT 1;
        """, (payload.trip_stop_log_id,))

        return {
            "message": "Delay incident successfully recorded and classified",
            "delay": latest
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to record delay: {str(e)}")


@router.get("/calculate-severity")
def test_delay_severity(seconds: int):
    """Calls PL/pgSQL function fn_calculate_delay_severity(seconds)."""
    query = "SELECT fn_calculate_delay_severity(%s) AS severity;"
    try:
        res = fetch_one(query, (seconds,))
        return res
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
