"""
TransitIQ API - Trip Dispatch & Execution Router
Manages daily trips, stop arrival logs, and executes stored procedure sp_create_trip.
"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from typing import Optional
from datetime import date, datetime
from ..database import fetch_all, fetch_one, execute_dml, execute_returning, get_db_cursor

router = APIRouter(prefix="/api/trips", tags=["Trip Operations & Dispatch"])


class TripCreate(BaseModel):
    schedule_id: int
    route_id: int
    bus_id: int
    driver_id: int
    service_date: date
    scheduled_start: datetime


class TripStatusUpdate(BaseModel):
    trip_status: str = Field(..., pattern="^(SCHEDULED|RUNNING|COMPLETED|CANCELLED)$")


@router.get("")
def get_trips(
    service_date: Optional[date] = None,
    status: Optional[str] = None,
    route_id: Optional[int] = None,
    limit: int = 50
):
    """Retrieves operational trips with joined route, bus, and driver metadata."""
    query = """
        SELECT
            t.trip_id,
            t.schedule_id,
            t.route_id,
            r.route_number,
            r.route_name,
            t.bus_id,
            b.registration_number,
            t.driver_id,
            d.first_name || ' ' || COALESCE(d.last_name, '') AS driver_name,
            t.service_date,
            t.scheduled_start,
            t.actual_start,
            t.actual_end,
            t.trip_status
        FROM trips t
        JOIN routes r ON t.route_id = r.route_id
        JOIN buses b ON t.bus_id = b.bus_id
        JOIN drivers d ON t.driver_id = d.driver_id
        WHERE 1=1
    """
    params = []
    if service_date:
        query += " AND t.service_date = %s"
        params.append(service_date)
    if status:
        query += " AND t.trip_status = %s"
        params.append(status.upper())
    if route_id:
        query += " AND t.route_id = %s"
        params.append(route_id)

    query += " ORDER BY t.scheduled_start DESC, t.trip_id DESC LIMIT %s;"
    params.append(limit)

    return fetch_all(query, tuple(params))


@router.get("/{trip_id}")
def get_trip_details(trip_id: int):
    """Retrieves trip header and all associated stop arrival logs."""
    trip_query = """
        SELECT
            t.trip_id,
            t.schedule_id,
            t.route_id,
            r.route_number,
            r.route_name,
            t.bus_id,
            b.registration_number,
            t.driver_id,
            d.first_name || ' ' || COALESCE(d.last_name, '') AS driver_name,
            t.service_date,
            t.scheduled_start,
            t.actual_start,
            t.actual_end,
            t.trip_status
        FROM trips t
        JOIN routes r ON t.route_id = r.route_id
        JOIN buses b ON t.bus_id = b.bus_id
        JOIN drivers d ON t.driver_id = d.driver_id
        WHERE t.trip_id = %s;
    """
    trip = fetch_one(trip_query, (trip_id,))
    if not trip:
        raise HTTPException(status_code=404, detail=f"Trip with ID {trip_id} not found")

    logs_query = """
        SELECT
            tsl.trip_stop_log_id,
            tsl.route_stop_id,
            rs.stop_sequence,
            s.stop_name,
            tsl.scheduled_arrival_at,
            tsl.actual_arrival_at,
            tsl.actual_departure_at,
            tsl.stop_status,
            COALESCE(pc.boarding_count, 0) AS boarding_count,
            COALESCE(pc.alighting_count, 0) AS alighting_count
        FROM trip_stop_logs tsl
        JOIN route_stops rs ON tsl.route_stop_id = rs.route_stop_id
        JOIN stops s ON rs.stop_id = s.stop_id
        LEFT JOIN passenger_counts pc ON tsl.trip_stop_log_id = pc.trip_stop_log_id
        WHERE tsl.trip_id = %s
        ORDER BY rs.stop_sequence ASC;
    """
    trip["stop_logs"] = fetch_all(logs_query, (trip_id,))
    return trip


@router.post("")
def dispatch_trip(payload: TripCreate):
    """
    Dispatches a new trip by executing stored procedure sp_create_trip.
    Enforces active bus/driver availability, operating day verification,
    and schedule ownership validations atomically.
    """
    try:
        with get_db_cursor(commit=True) as cur:
            cur.execute("""
                CALL sp_create_trip(
                    %s, %s, %s, %s, %s, %s, NULL
                );
            """, (
                payload.schedule_id,
                payload.route_id,
                payload.bus_id,
                payload.driver_id,
                payload.service_date,
                payload.scheduled_start
            ))
            # Fetch newly created trip
            new_trip_id_row = cur.fetchone()
            new_trip_id = new_trip_id_row['p_trip_id'] if new_trip_id_row and 'p_trip_id' in new_trip_id_row else None

        if not new_trip_id:
            # Fallback fetch latest trip for bus and schedule
            latest = fetch_one("""
                SELECT trip_id FROM trips
                WHERE schedule_id = %s AND bus_id = %s AND service_date = %s
                ORDER BY trip_id DESC LIMIT 1;
            """, (payload.schedule_id, payload.bus_id, payload.service_date))
            new_trip_id = latest['trip_id'] if latest else None

        return {
            "message": "Trip successfully dispatched",
            "trip_id": new_trip_id,
            "status": "SCHEDULED"
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Dispatch validation failed: {str(e)}")


@router.put("/{trip_id}/status")
def update_trip_status(trip_id: int, payload: TripStatusUpdate):
    """Updates operational trip status (e.g. from SCHEDULED to RUNNING or COMPLETED)."""
    now = datetime.now()
    if payload.trip_status == "RUNNING":
        query = """
            UPDATE trips
            SET trip_status = %s, actual_start = COALESCE(actual_start, %s)
            WHERE trip_id = %s
            RETURNING *;
        """
        res = execute_returning(query, (payload.trip_status, now, trip_id))
    elif payload.trip_status == "COMPLETED":
        query = """
            UPDATE trips
            SET trip_status = %s, actual_end = COALESCE(actual_end, %s)
            WHERE trip_id = %s
            RETURNING *;
        """
        res = execute_returning(query, (payload.trip_status, now, trip_id))
    else:
        query = """
            UPDATE trips
            SET trip_status = %s
            WHERE trip_id = %s
            RETURNING *;
        """
        res = execute_returning(query, (payload.trip_status, trip_id))

    if not res:
        raise HTTPException(status_code=404, detail=f"Trip with ID {trip_id} not found")
    return {"message": f"Trip {trip_id} status updated to {payload.trip_status}", "trip": res}
