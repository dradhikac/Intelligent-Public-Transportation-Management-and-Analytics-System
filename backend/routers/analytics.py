"""
TransitIQ API - Advanced Analytics & Executive Dashboard Router
Exposes KPIs, 5 production analytical views, and cross-cutting transit metrics.
"""

from fastapi import APIRouter
from ..database import fetch_all, fetch_one

router = APIRouter(prefix="/api/analytics", tags=["Executive Analytics & Views"])


@router.get("/kpis")
def get_executive_kpis():
    """Calculates top-level operational KPIs for the TransitIQ executive dashboard."""
    kpis_query = """
        SELECT
            (SELECT COUNT(*) FROM buses) AS total_buses,
            (SELECT COUNT(*) FROM buses WHERE status = 'ACTIVE') AS active_buses,
            (SELECT COUNT(*) FROM routes WHERE status = 'ACTIVE') AS active_routes,
            (SELECT COUNT(*) FROM trips) AS total_trips,
            (SELECT COUNT(*) FROM trips WHERE trip_status = 'RUNNING') AS running_trips,
            (SELECT COUNT(*) FROM trips WHERE trip_status = 'COMPLETED') AS completed_trips,
            (SELECT COUNT(*) FROM drivers WHERE status = 'AVAILABLE') AS available_drivers,
            (SELECT COALESCE(SUM(boarding_count), 0) FROM passenger_counts) AS total_passengers_served,
            (SELECT COUNT(*) FROM delay_records WHERE severity = 'SEVERE') AS severe_delays_count,
            (SELECT COUNT(*) FROM maintenance_records WHERE maintenance_status = 'PENDING') AS pending_maintenance_count;
    """
    kpis = fetch_one(kpis_query) or {}

    # Calculate punctuality percentage
    completion_rate_query = """
        SELECT
            ROUND(100.0 * COUNT(CASE WHEN trip_status = 'COMPLETED' THEN 1 END) / NULLIF(COUNT(*), 0), 1) AS on_time_rate_pct
        FROM trips;
    """
    rate = fetch_one(completion_rate_query)
    kpis["on_time_rate_pct"] = rate["on_time_rate_pct"] if rate else 100.0

    return kpis


@router.get("/fleet-summary")
def get_fleet_summary():
    """Queries production analytical view vw_fleet_summary."""
    return fetch_all("SELECT * FROM vw_fleet_summary ORDER BY bus_id ASC;")


@router.get("/route-performance")
def get_route_performance():
    """Queries production analytical view vw_route_performance."""
    return fetch_all("SELECT * FROM vw_route_performance ORDER BY total_scheduled_trips DESC;")


@router.get("/passenger-demand")
def get_passenger_demand():
    """Queries production analytical view vw_passenger_demand."""
    return fetch_all("SELECT * FROM vw_passenger_demand ORDER BY total_footfall DESC;")


@router.get("/delay-analysis")
def get_delay_analysis():
    """Queries production analytical view vw_delay_analysis."""
    return fetch_all("SELECT * FROM vw_delay_analysis ORDER BY delay_seconds DESC;")


@router.get("/driver-performance")
def get_driver_performance():
    """Queries production analytical view vw_driver_performance."""
    return fetch_all("SELECT * FROM vw_driver_performance ORDER BY total_assigned_trips DESC;")
