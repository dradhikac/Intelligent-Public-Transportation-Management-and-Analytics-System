"""
TransitIQ API - Routes & Network Geometry Router
Covers routes, transit stops, route stops sequence, schedules, and route analytics.
"""

from fastapi import APIRouter, HTTPException
from typing import Optional
from ..database import fetch_all, fetch_one

router = APIRouter(prefix="/api/routes", tags=["Routes & Network"])


@router.get("")
def get_routes(status: Optional[str] = None):
    """Retrieves all transit lines/corridors."""
    query = "SELECT * FROM routes"
    params = ()
    if status:
        query += " WHERE status = %s"
        params = (status.upper(),)
    query += " ORDER BY route_number ASC;"
    return fetch_all(query, params)


@router.get("/{route_id}")
def get_route_details(route_id: int):
    """Retrieves route header and ordered stop progression."""
    route_query = "SELECT * FROM routes WHERE route_id = %s;"
    route = fetch_one(route_query, (route_id,))
    if not route:
        raise HTTPException(status_code=404, detail=f"Route with ID {route_id} not found")

    stops_query = """
        SELECT
            rs.route_stop_id,
            rs.stop_sequence,
            rs.distance_from_start_km,
            rs.estimated_travel_minutes,
            s.stop_id,
            s.stop_name,
            s.location_description,
            s.latitude,
            s.longitude,
            s.is_active
        FROM route_stops rs
        JOIN stops s ON rs.stop_id = s.stop_id
        WHERE rs.route_id = %s
        ORDER BY rs.stop_sequence ASC;
    """
    stops = fetch_all(stops_query, (route_id,))
    route["stops"] = stops
    return route


@router.get("/stops/all")
def get_all_stops():
    """Returns all geographic transit stops with coordinates for mapping."""
    query = """
        SELECT
            stop_id,
            stop_name,
            location_description,
            latitude,
            longitude,
            is_active
        FROM stops
        ORDER BY stop_name ASC;
    """
    return fetch_all(query)


@router.get("/schedules/all")
def get_schedules(route_id: Optional[int] = None):
    """Returns scheduled timetables and departure/arrival times."""
    query = """
        SELECT
            s.schedule_id,
            s.route_id,
            r.route_number,
            r.route_name,
            s.schedule_name,
            s.departure_time,
            s.arrival_time,
            s.frequency_minutes,
            s.effective_from,
            s.effective_until,
            s.status
        FROM schedules s
        JOIN routes r ON s.route_id = r.route_id
        WHERE 1=1
    """
    params = []
    if route_id:
        query += " AND s.route_id = %s"
        params.append(route_id)
    query += " ORDER BY s.departure_time ASC;"
    return fetch_all(query, tuple(params))


@router.get("/{route_id}/performance-function")
def get_route_performance_function(route_id: int):
    """Executes PL/pgSQL function fn_get_route_performance(route_id)."""
    query = "SELECT * FROM fn_get_route_performance(%s);"
    try:
        res = fetch_one(query, (route_id,))
        if not res:
            raise HTTPException(status_code=404, detail="No route performance record found")
        return res
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/views/performance")
def get_route_performance_view():
    """Queries production view vw_route_performance."""
    query = "SELECT * FROM vw_route_performance ORDER BY total_scheduled_trips DESC;"
    return fetch_all(query)
