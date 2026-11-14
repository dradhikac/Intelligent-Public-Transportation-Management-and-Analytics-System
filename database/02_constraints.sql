
-- ==========================================
-- TransitIQ: Performance Indexes
-- ==========================================

-- Fleet
CREATE INDEX idx_buses_bus_type
ON buses(bus_type_id);

CREATE INDEX idx_buses_status
ON buses(status);

CREATE INDEX idx_maintenance_bus
ON maintenance_records(bus_id);

-- Routes
CREATE INDEX idx_route_stops_route
ON route_stops(route_id);

CREATE INDEX idx_route_stops_stop
ON route_stops(stop_id);

-- Drivers
CREATE INDEX idx_drivers_status
ON drivers(status);

CREATE INDEX idx_drivers_license_expiry
ON drivers(license_expiry_date);

-- Schedules
CREATE INDEX idx_schedules_route
ON schedules(route_id);

CREATE INDEX idx_schedule_stop_route
ON schedule_stop_times(route_id);

-- Trips
CREATE INDEX idx_trips_route_date
ON trips(route_id, service_date);

CREATE INDEX idx_trips_bus
ON trips(bus_id);

CREATE INDEX idx_trips_driver
ON trips(driver_id);

CREATE INDEX idx_trips_status
ON trips(trip_status);

-- Trip logs
CREATE INDEX idx_trip_logs_trip
ON trip_stop_logs(trip_id);

CREATE INDEX idx_trip_logs_route
ON trip_stop_logs(route_id);

-- Passenger analytics
CREATE INDEX idx_passenger_recorded_at
ON passenger_counts(recorded_at);

-- Delay analytics
CREATE INDEX idx_delay_reason
ON delay_records(reason_id);

CREATE INDEX idx_delay_recorded_at
ON delay_records(recorded_at);

