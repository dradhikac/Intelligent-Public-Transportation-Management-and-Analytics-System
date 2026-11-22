"""
TransitIQ API - Passenger Telemetry & Footfall Router
Manages passenger boarding/alighting counts and executes sp_record_passenger_count.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from typing import Optional
from ..database import fetch_all, fetch_one, get_db_cursor

router = APIRouter(prefix="/api/passengers", tags=["Passenger Counts & Demand"])


class PassengerCountCreate(BaseModel):
    trip_stop_log_id: int
    boarding_count: int = Field(default=0, ge=0)
    alighting_count: int = Field(default=0, ge=0)


@router.get("/demand")
def get_passenger_demand():
    """Queries production view vw_passenger_demand for stop-level footfall metrics."""
    query = "SELECT * FROM vw_passenger_demand ORDER BY total_footfall DESC;"
    return fetch_all(query)


@router.get("/stop/{stop_id}/demand-function")
def get_stop_demand_function(stop_id: int):
    """Executes PL/pgSQL function fn_get_stop_demand(stop_id)."""
    query = "SELECT * FROM fn_get_stop_demand(%s);"
    try:
        res = fetch_one(query, (stop_id,))
        if not res:
            raise HTTPException(status_code=404, detail="No demand data found for stop")
        return res
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/record")
def record_passenger_count(payload: PassengerCountCreate):
    """
    Records boarding and alighting passenger counts using stored procedure
    sp_record_passenger_count. Enforces non-negative counts and updates stop logs.
    """
    try:
        with get_db_cursor(commit=True) as cur:
            cur.execute("""
                CALL sp_record_passenger_count(%s, %s, %s);
            """, (payload.trip_stop_log_id, payload.boarding_count, payload.alighting_count))

        # Fetch recorded record
        rec = fetch_one("""
            SELECT * FROM passenger_counts
            WHERE trip_stop_log_id = %s;
        """, (payload.trip_stop_log_id,))

        return {
            "message": "Passenger count recorded successfully",
            "record": rec
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to record passenger count: {str(e)}")


@router.get("/recent")
def get_recent_passenger_logs(limit: int = 50):
    """Retrieves recent passenger counts joined with route and stop names."""
    query = """
        SELECT
            pc.passenger_count_id,
            pc.trip_stop_log_id,
            t.trip_id,
            r.route_number,
            s.stop_name,
            pc.boarding_count,
            pc.alighting_count,
            (pc.boarding_count + pc.alighting_count) AS total_footfall,
            pc.recorded_at
        FROM passenger_counts pc
        JOIN trip_stop_logs tsl ON pc.trip_stop_log_id = tsl.trip_stop_log_id
        JOIN trips t ON tsl.trip_id = t.trip_id
        JOIN routes r ON t.route_id = r.route_id
        JOIN route_stops rs ON tsl.route_stop_id = rs.route_stop_id
        JOIN stops s ON rs.stop_id = s.stop_id
        ORDER BY pc.recorded_at DESC
        LIMIT %s;
    """
    return fetch_all(query, (limit,))
