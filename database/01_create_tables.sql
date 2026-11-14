
-- =====================================================
-- PROJECT: TransitIQ
-- DATABASE: transitiq_db
-- SCRIPT: 01_create_tables.sql
-- PURPOSE: Create all 17 relational tables
-- =====================================================

-- 1. BUS TYPES
CREATE TABLE bus_types (
    bus_type_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type_name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    seating_capacity INTEGER NOT NULL CHECK (seating_capacity > 0),
    standing_capacity INTEGER DEFAULT 0 CHECK (standing_capacity >= 0)
);

-- 2. BUSES
CREATE TABLE buses (
    bus_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    registration_number VARCHAR(20) UNIQUE NOT NULL,
    bus_type_id BIGINT NOT NULL,
    manufacturer VARCHAR(100),
    model VARCHAR(100),
    manufacturing_year INTEGER CHECK (manufacturing_year BETWEEN 1900 AND 2100),
    purchase_date DATE,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'MAINTENANCE', 'INACTIVE', 'RETIRED')),
    last_service_date DATE,
    CONSTRAINT fk_bus_type
        FOREIGN KEY (bus_type_id) REFERENCES bus_types(bus_type_id),
    CHECK (purchase_date IS NULL OR last_service_date IS NULL
           OR last_service_date >= purchase_date)
);

-- 3. MAINTENANCE RECORDS
CREATE TABLE maintenance_records (
    maintenance_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bus_id BIGINT NOT NULL,
    maintenance_type VARCHAR(50) NOT NULL,
    description TEXT,
    maintenance_date DATE NOT NULL,
    next_service_date DATE,
    maintenance_cost NUMERIC(12,2) DEFAULT 0 CHECK (maintenance_cost >= 0),
    maintenance_status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
        CHECK (maintenance_status IN ('PENDING', 'IN_PROGRESS', 'COMPLETED')),
    FOREIGN KEY (bus_id) REFERENCES buses(bus_id),
    CHECK (next_service_date IS NULL OR next_service_date >= maintenance_date)
);

-- 4. ROUTES
CREATE TABLE routes (
    route_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    route_number VARCHAR(20) UNIQUE NOT NULL,
    route_name VARCHAR(100) NOT NULL,
    start_location VARCHAR(100) NOT NULL,
    end_location VARCHAR(100) NOT NULL,
    total_distance_km NUMERIC(8,2) CHECK (total_distance_km > 0),
    estimated_duration_minutes INTEGER CHECK (estimated_duration_minutes > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED'))
);

-- 5. STOPS
CREATE TABLE stops (
    stop_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    stop_name VARCHAR(100) NOT NULL,
    location_description TEXT,
    latitude NUMERIC(10,7),
    longitude NUMERIC(10,7),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    CHECK ((latitude IS NULL AND longitude IS NULL)
        OR (latitude IS NOT NULL AND longitude IS NOT NULL))
);

-- 6. ROUTE STOPS
CREATE TABLE route_stops (
    route_stop_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    route_id BIGINT NOT NULL,
    stop_id BIGINT NOT NULL,
    stop_sequence INTEGER NOT NULL CHECK (stop_sequence > 0),
    distance_from_start_km NUMERIC(8,2) DEFAULT 0
        CHECK (distance_from_start_km >= 0),
    estimated_travel_minutes INTEGER
        CHECK (estimated_travel_minutes >= 0),

    FOREIGN KEY (route_id) REFERENCES routes(route_id),
    FOREIGN KEY (stop_id) REFERENCES stops(stop_id),

    UNIQUE (route_id, stop_id),
    UNIQUE (route_id, stop_sequence),
    UNIQUE (route_stop_id, route_id)
);

-- 7. DRIVERS
CREATE TABLE drivers (
    driver_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_code VARCHAR(20) UNIQUE NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50),
    phone_number VARCHAR(15),
    license_number VARCHAR(30) UNIQUE NOT NULL,
    license_expiry_date DATE NOT NULL,
    date_of_joining DATE,
    status VARCHAR(20) NOT NULL DEFAULT 'AVAILABLE'
        CHECK (status IN ('AVAILABLE', 'ON_DUTY', 'ON_LEAVE', 'INACTIVE'))
);

-- 8. SCHEDULES
CREATE TABLE schedules (
    schedule_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    route_id BIGINT NOT NULL,
    schedule_name VARCHAR(100),
    departure_time TIME NOT NULL,
    arrival_time TIME NOT NULL,
    frequency_minutes INTEGER CHECK (frequency_minutes > 0),
    effective_from DATE NOT NULL,
    effective_until DATE,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED')),

    FOREIGN KEY (route_id) REFERENCES routes(route_id),
    UNIQUE (schedule_id, route_id),
    CHECK (effective_until IS NULL OR effective_until >= effective_from)
);

-- 9. OPERATING DAYS
CREATE TABLE operating_days (
    day_id SMALLINT PRIMARY KEY,
    day_name VARCHAR(15) UNIQUE NOT NULL
);

-- 10. SCHEDULE OPERATING DAYS
CREATE TABLE schedule_operating_days (
    schedule_id BIGINT NOT NULL,
    day_id SMALLINT NOT NULL,

    PRIMARY KEY (schedule_id, day_id),

    FOREIGN KEY (schedule_id) REFERENCES schedules(schedule_id),
    FOREIGN KEY (day_id) REFERENCES operating_days(day_id)
);

-- 11. SCHEDULE STOP TIMES
CREATE TABLE schedule_stop_times (
    schedule_stop_time_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    schedule_id BIGINT NOT NULL,
    route_id BIGINT NOT NULL,
    route_stop_id BIGINT NOT NULL,
    scheduled_arrival TIME NOT NULL,
    scheduled_departure TIME NOT NULL,

    FOREIGN KEY (schedule_id, route_id)
        REFERENCES schedules(schedule_id, route_id),

    FOREIGN KEY (route_stop_id, route_id)
        REFERENCES route_stops(route_stop_id, route_id),

    UNIQUE (schedule_id, route_stop_id)
);

-- 12. TRIPS
CREATE TABLE trips (
    trip_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    schedule_id BIGINT NOT NULL,
    route_id BIGINT NOT NULL,
    bus_id BIGINT NOT NULL,
    driver_id BIGINT NOT NULL,
    service_date DATE NOT NULL,
    scheduled_start TIMESTAMPTZ NOT NULL,
    actual_start TIMESTAMPTZ,
    actual_end TIMESTAMPTZ,
    trip_status VARCHAR(20) NOT NULL DEFAULT 'SCHEDULED'
        CHECK (trip_status IN ('SCHEDULED', 'RUNNING', 'COMPLETED', 'CANCELLED')),

    FOREIGN KEY (schedule_id, route_id)
        REFERENCES schedules(schedule_id, route_id),

    FOREIGN KEY (bus_id) REFERENCES buses(bus_id),
    FOREIGN KEY (driver_id) REFERENCES drivers(driver_id),

    UNIQUE (trip_id, route_id),

    CHECK (actual_end IS NULL OR actual_start IS NOT NULL),
    CHECK (actual_end IS NULL OR actual_end >= actual_start)
);

-- 13. TRIP STOP LOGS
CREATE TABLE trip_stop_logs (
    trip_stop_log_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_id BIGINT NOT NULL,
    route_id BIGINT NOT NULL,
    route_stop_id BIGINT NOT NULL,
    scheduled_arrival_at TIMESTAMPTZ,
    actual_arrival_at TIMESTAMPTZ,
    actual_departure_at TIMESTAMPTZ,
    stop_status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
        CHECK (stop_status IN ('PENDING', 'REACHED', 'SKIPPED')),

    FOREIGN KEY (trip_id, route_id)
        REFERENCES trips(trip_id, route_id),

    FOREIGN KEY (route_stop_id, route_id)
        REFERENCES route_stops(route_stop_id, route_id),

    UNIQUE (trip_id, route_stop_id),

    CHECK (actual_departure_at IS NULL
        OR actual_arrival_at IS NOT NULL),

    CHECK (actual_departure_at IS NULL
        OR actual_departure_at >= actual_arrival_at)
);

-- 14. PASSENGER COUNTS
CREATE TABLE passenger_counts (
    passenger_count_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_stop_log_id BIGINT NOT NULL UNIQUE,
    boarding_count INTEGER NOT NULL DEFAULT 0 CHECK (boarding_count >= 0),
    alighting_count INTEGER NOT NULL DEFAULT 0 CHECK (alighting_count >= 0),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (trip_stop_log_id)
        REFERENCES trip_stop_logs(trip_stop_log_id)
);

-- 15. DELAY REASONS
CREATE TABLE delay_reasons (
    reason_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reason_name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT
);

-- 16. DELAY RECORDS
CREATE TABLE delay_records (
    delay_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_stop_log_id BIGINT NOT NULL,
    reason_id BIGINT NOT NULL,
    delay_seconds INTEGER NOT NULL CHECK (delay_seconds >= 0),
    severity VARCHAR(20) NOT NULL
        CHECK (severity IN ('MINOR', 'MODERATE', 'SEVERE')),
    remarks TEXT,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (trip_stop_log_id)
        REFERENCES trip_stop_logs(trip_stop_log_id),

    FOREIGN KEY (reason_id)
        REFERENCES delay_reasons(reason_id)
);

-- 17. AUDIT LOGS
CREATE TABLE audit_logs (
    audit_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id BIGINT,
    operation VARCHAR(10) NOT NULL
        CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_data JSONB,
    new_data JSONB,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(100) DEFAULT CURRENT_USER
);

-- =====================================================
-- END OF TABLE CREATION
-- =====================================================

-- List all tables in the public schema

SELECT
    table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;


