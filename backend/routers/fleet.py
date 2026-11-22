"""
TransitIQ API - Fleet Management Router
Covers buses, bus types, maintenance records, and PL/pgSQL function calls.
"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import date
from ..database import fetch_all, fetch_one, execute_dml, execute_returning

router = APIRouter(prefix="/api/fleet", tags=["Fleet Management"])


class MaintenanceCreate(BaseModel):
    bus_id: int
    maintenance_type: str
    description: Optional[str] = None
    maintenance_date: date
    next_service_date: Optional[date] = None
    maintenance_cost: float = Field(default=0.0, ge=0.0)
    maintenance_status: str = Field(default="PENDING", pattern="^(PENDING|IN_PROGRESS|COMPLETED)$")


class BusStatusUpdate(BaseModel):
    status: str = Field(..., pattern="^(ACTIVE|MAINTENANCE|INACTIVE|RETIRED)$")


@router.get("/buses")
def get_buses(status: Optional[str] = None):
    """Retrieves all fleet buses with their specifications and operational status."""
    query = """
        SELECT
            b.bus_id,
            b.registration_number,
            b.manufacturer,
            b.model,
            b.manufacturing_year,
            b.status,
            b.purchase_date,
            b.last_service_date,
            bt.bus_type_id,
            bt.type_name AS bus_type,
            bt.seating_capacity,
            bt.standing_capacity,
            (bt.seating_capacity + bt.standing_capacity) AS total_capacity
        FROM buses b
        JOIN bus_types bt ON b.bus_type_id = bt.bus_type_id
    """
    params = ()
    if status:
        query += " WHERE b.status = %s"
        params = (status.upper(),)
    query += " ORDER BY b.bus_id ASC;"
    return fetch_all(query, params)


@router.get("/buses/{bus_id}")
def get_bus_details(bus_id: int):
    """Retrieves detailed record for an individual bus asset."""
    query = """
        SELECT
            b.bus_id,
            b.registration_number,
            b.manufacturer,
            b.model,
            b.manufacturing_year,
            b.status,
            b.purchase_date,
            b.last_service_date,
            bt.bus_type_id,
            bt.type_name AS bus_type,
            bt.seating_capacity,
            bt.standing_capacity,
            (bt.seating_capacity + bt.standing_capacity) AS total_capacity
        FROM buses b
        JOIN bus_types bt ON b.bus_type_id = bt.bus_type_id
        WHERE b.bus_id = %s;
    """
    bus = fetch_one(query, (bus_id,))
    if not bus:
        raise HTTPException(status_code=404, detail=f"Bus with ID {bus_id} not found")
    return bus


@router.put("/buses/{bus_id}/status")
def update_bus_status(bus_id: int, payload: BusStatusUpdate):
    """Updates the operational status of a bus."""
    query = """
        UPDATE buses
        SET status = %s
        WHERE bus_id = %s
        RETURNING bus_id, registration_number, status;
    """
    result = execute_returning(query, (payload.status, bus_id))
    if not result:
        raise HTTPException(status_code=404, detail=f"Bus with ID {bus_id} not found")
    return {"message": "Status updated successfully", "bus": result}


@router.get("/buses/{bus_id}/function-status")
def get_bus_function_status(bus_id: int):
    """Calls PL/pgSQL function fn_get_bus_status(bus_id) and returns composite status."""
    query = "SELECT * FROM fn_get_bus_status(%s);"
    try:
        result = fetch_one(query, (bus_id,))
        if not result:
            raise HTTPException(status_code=404, detail="No status returned for bus")
        return result
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/buses/{bus_id}/utilization")
def get_bus_utilization(bus_id: int):
    """Calls PL/pgSQL function fn_get_bus_utilization(bus_id)."""
    query = "SELECT * FROM fn_get_bus_utilization(%s);"
    try:
        result = fetch_one(query, (bus_id,))
        if not result:
            raise HTTPException(status_code=404, detail="No utilization metrics returned")
        return result
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/types")
def get_bus_types():
    """Lists all bus types, seating, and standing capacity classifications."""
    query = "SELECT * FROM bus_types ORDER BY bus_type_id ASC;"
    return fetch_all(query)


@router.get("/maintenance")
def get_maintenance_records(bus_id: Optional[int] = None, status: Optional[str] = None):
    """Lists maintenance events, costs, and inspection statuses."""
    query = """
        SELECT
            mr.maintenance_id,
            mr.bus_id,
            b.registration_number,
            mr.maintenance_type,
            mr.description,
            mr.maintenance_date,
            mr.next_service_date,
            mr.maintenance_cost,
            mr.maintenance_status
        FROM maintenance_records mr
        JOIN buses b ON mr.bus_id = b.bus_id
        WHERE 1=1
    """
    params = []
    if bus_id:
        query += " AND mr.bus_id = %s"
        params.append(bus_id)
    if status:
        query += " AND mr.maintenance_status = %s"
        params.append(status.upper())
    query += " ORDER BY mr.maintenance_date DESC, mr.maintenance_id DESC;"
    return fetch_all(query, tuple(params))


@router.post("/maintenance")
def create_maintenance_record(payload: MaintenanceCreate):
    """Registers a new vehicle maintenance work order."""
    query = """
        INSERT INTO maintenance_records (
            bus_id, maintenance_type, description, maintenance_date,
            next_service_date, maintenance_cost, maintenance_status
        ) VALUES (%s, %s, %s, %s, %s, %s, %s)
        RETURNING *;
    """
    params = (
        payload.bus_id, payload.maintenance_type, payload.description,
        payload.maintenance_date, payload.next_service_date,
        payload.maintenance_cost, payload.maintenance_status
    )
    result = execute_returning(query, params)
    return {"message": "Maintenance record created", "maintenance": result}


@router.post("/maintenance/{maintenance_id}/complete")
def complete_maintenance(maintenance_id: int):
    """
    Marks a maintenance record as COMPLETED.
    PostgreSQL trigger trg_sync_bus_maintenance_date automatically updates buses.last_service_date.
    """
    query = """
        UPDATE maintenance_records
        SET maintenance_status = 'COMPLETED'
        WHERE maintenance_id = %s
        RETURNING *;
    """
    result = execute_returning(query, (maintenance_id,))
    if not result:
        raise HTTPException(status_code=404, detail="Maintenance record not found")
    return {"message": "Maintenance completed; bus last_service_date synchronized", "maintenance": result}


@router.get("/summary")
def get_fleet_summary_view():
    """Queries production view vw_fleet_summary."""
    query = "SELECT * FROM vw_fleet_summary ORDER BY bus_id ASC;"
    return fetch_all(query)
