"""
TransitIQ - Intelligent Public Transportation Management and Analytics System
FastAPI Main Application Entry Point
"""

import os
from pathlib import Path
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import RedirectResponse, FileResponse

from .config import settings
from .database import init_db_pool, close_db_pool
from .routers import fleet, routes, trips, passengers, delays, drivers, analytics, audit, system


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Initialize PostgreSQL connection pool
    try:
        init_db_pool()
    except Exception as e:
        print(f"[WARNING] Database connection initialization error: {e}")
    yield
    # Shutdown: Close pool
    close_db_pool()


app = FastAPI(
    title="TransitIQ API - Intelligent Public Transportation Management & Analytics",
    description="Enterprise REST API for TransitIQ operating over PostgreSQL 18. Provides endpoints for Fleet, Trips, Routes, Passenger Telemetry, Delays, Analytics Views, and Security Auditing.",
    version=settings.APP_VERSION,
    lifespan=lifespan
)

# Configure Cross-Origin Resource Sharing (CORS)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount API Routers
app.include_router(system.router)
app.include_router(analytics.router)
app.include_router(fleet.router)
app.include_router(routes.router)
app.include_router(trips.router)
app.include_router(passengers.router)
app.include_router(delays.router)
app.include_router(drivers.router)
app.include_router(audit.router)

# Resolve Frontend Directory Path
frontend_dir = Path(__file__).resolve().parent.parent / "frontend"
static_dir = frontend_dir / "static"

if static_dir.exists():
    app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

@app.get("/", include_in_schema=False)
def root():
    """Serves the frontend dashboard or redirects to Swagger UI."""
    index_file = frontend_dir / "index.html"
    if index_file.exists():
        return FileResponse(str(index_file))
    return RedirectResponse(url="/docs")


@app.get("/dashboard", include_in_schema=False)
def dashboard():
    """Serves the frontend dashboard."""
    index_file = frontend_dir / "index.html"
    if index_file.exists():
        return FileResponse(str(index_file))
    return RedirectResponse(url="/docs")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("backend.main:app", host=settings.HOST, port=settings.PORT, reload=settings.DEBUG)
