

-- =====================================================
-- TransitIQ: OPERATIONAL DATA GENERATION
-- PART A: FLEET, DRIVERS, ROUTES AND STOPS
-- =====================================================

BEGIN;

-- 1. GENERATE 50 BUSES

WITH bus_type_ranks AS (
    SELECT bus_type_id,
           ROW_NUMBER() OVER (ORDER BY bus_type_id) AS rn
    FROM bus_types
)
INSERT INTO buses (
    registration_number,
    bus_type_id,
    manufacturer,
    model,
    manufacturing_year,
    purchase_date,
    status,
    last_service_date
)
SELECT
    'TIQ-' || LPAD(g.n::TEXT, 4, '0'),
    bt.bus_type_id,
    CASE g.n % 4
        WHEN 0 THEN 'Tata Motors'
        WHEN 1 THEN 'Ashok Leyland'
        WHEN 2 THEN 'Volvo'
        ELSE 'Eicher'
    END,
    'City Bus ' || g.n,
    2018 + (g.n % 8),
    CURRENT_DATE - (g.n % 1000),
    CASE
        WHEN g.n % 15 = 0 THEN 'MAINTENANCE'
        WHEN g.n % 20 = 0 THEN 'INACTIVE'
        ELSE 'ACTIVE'
    END,
    CURRENT_DATE - (g.n % 90)
FROM generate_series(1, 50) AS g(n)
JOIN bus_type_ranks bt
    ON bt.rn = ((g.n - 1) % 4) + 1;


-- 2. GENERATE 40 DRIVERS

INSERT INTO drivers (
    employee_code,
    first_name,
    last_name,
    phone_number,
    license_number,
    license_expiry_date,
    date_of_joining,
    status
)
SELECT
    'DRV-' || LPAD(g.n::TEXT, 3, '0'),
    'Driver' || g.n,
    'Transit',
    '90000' || LPAD(g.n::TEXT, 5, '0'),
    'LIC-' || LPAD(g.n::TEXT, 5, '0'),
    CURRENT_DATE + ((g.n % 5) * 90) - 60,
    CURRENT_DATE - (g.n * 20),
    CASE
        WHEN g.n % 12 = 0 THEN 'ON_LEAVE'
        WHEN g.n % 10 = 0 THEN 'INACTIVE'
        ELSE 'AVAILABLE'
    END
FROM generate_series(1, 40) AS g(n);


-- 3. GENERATE 25 ROUTES

INSERT INTO routes (
    route_number,
    route_name,
    start_location,
    end_location,
    total_distance_km,
    estimated_duration_minutes,
    status
)
SELECT
    'R' || LPAD(g.n::TEXT, 3, '0'),
    'City Route ' || g.n,
    'Terminal ' || g.n,
    'Destination ' || g.n,
    15 + (g.n % 10) * 1.5,
    90 + (g.n % 4) * 10,
    'ACTIVE'
FROM generate_series(1, 25) AS g(n);


-- 4. GENERATE 100 BUS STOPS

INSERT INTO stops (
    stop_name,
    location_description,
    is_active
)
SELECT
    'Transit Stop ' || LPAD(g.n::TEXT, 3, '0'),
    'Sample city bus stop ' || g.n,
    TRUE
FROM generate_series(1, 100) AS g(n);


-- 5. ASSIGN 10 STOPS TO EACH ROUTE
-- Stops are shared across different routes.

INSERT INTO route_stops (
    route_id,
    stop_id,
    stop_sequence,
    distance_from_start_km,
    estimated_travel_minutes
)
SELECT
    r.route_id,
    s.stop_id,
    seq.n,
    seq.n * 1.5,
    8
FROM generate_series(1, 25) AS rn(n)
JOIN routes r
    ON r.route_number = 'R' || LPAD(rn.n::TEXT, 3, '0')
CROSS JOIN generate_series(1, 10) AS seq(n)
JOIN stops s
    ON s.stop_name =
       'Transit Stop ' ||
       LPAD((((rn.n * 7 + seq.n * 3 - 1) % 100) + 1)::TEXT, 3, '0');


-- 6. GENERATE MAINTENANCE RECORDS

INSERT INTO maintenance_records (
    bus_id,
    maintenance_type,
    description,
    maintenance_date,
    next_service_date,
    maintenance_cost,
    maintenance_status
)
SELECT
    b.bus_id,
    CASE g.n % 3
        WHEN 0 THEN 'Engine Service'
        WHEN 1 THEN 'Brake Inspection'
        ELSE 'General Maintenance'
    END,
    'Routine maintenance record ' || g.n,
    CURRENT_DATE - (g.n * 3),
    CURRENT_DATE - (g.n * 3) + 90,
    1500 + (g.n % 10) * 500,
    'COMPLETED'
FROM generate_series(1, 100) AS g(n)
JOIN buses b
    ON b.registration_number =
       'TIQ-' || LPAD(((g.n - 1) % 50 + 1)::TEXT, 4, '0');


-- =====================================================
-- END OF PART A
-- =====================================================


-- =====================================================
-- PART B: SCHEDULE MANAGEMENT
-- =====================================================

-- 7. GENERATE ONE SCHEDULE PER ROUTE

INSERT INTO schedules (
    route_id,
    schedule_name,
    departure_time,
    arrival_time,
    frequency_minutes,
    effective_from,
    effective_until,
    status
)
SELECT
    r.route_id,
    'Schedule ' || r.route_number,
    TIME '05:00' + ((g.n - 1) * INTERVAL '20 minutes'),
    TIME '05:00' + ((g.n - 1) * INTERVAL '20 minutes')
        + (r.estimated_duration_minutes * INTERVAL '1 minute'),
    60,
    CURRENT_DATE - 30,
    NULL,
    'ACTIVE'
FROM generate_series(1, 25) AS g(n)
JOIN routes r
    ON r.route_number = 'R' || LPAD(g.n::TEXT, 3, '0');


-- 8. ASSIGN ALL SEVEN DAYS TO EVERY SCHEDULE

INSERT INTO schedule_operating_days (
    schedule_id,
    day_id
)
SELECT
    s.schedule_id,
    od.day_id
FROM schedules s
CROSS JOIN operating_days od;


-- 9. GENERATE PLANNED ARRIVAL AND DEPARTURE
-- TIMES FOR ALL 10 STOPS ON EACH ROUTE.

INSERT INTO schedule_stop_times (
    schedule_id,
    route_id,
    route_stop_id,
    scheduled_arrival,
    scheduled_departure
)
SELECT
    s.schedule_id,
    s.route_id,
    rs.route_stop_id,

    s.departure_time +
        (
            COALESCE(
                SUM(rs.estimated_travel_minutes) OVER (
                    PARTITION BY s.schedule_id
                    ORDER BY rs.stop_sequence
                    ROWS BETWEEN UNBOUNDED PRECEDING
                    AND 1 PRECEDING
                ),
                0
            ) * INTERVAL '1 minute'
        ),

    s.departure_time +
        (
            COALESCE(
                SUM(rs.estimated_travel_minutes) OVER (
                    PARTITION BY s.schedule_id
                    ORDER BY rs.stop_sequence
                    ROWS BETWEEN UNBOUNDED PRECEDING
                    AND 1 PRECEDING
                ),
                0
            ) * INTERVAL '1 minute'
        ) + INTERVAL '2 minutes'

FROM schedules s
JOIN route_stops rs
    ON rs.route_id = s.route_id;


-- =====================================================
-- END OF PART B
-- =====================================================


-- =====================================================
-- PART C: TRIP EXECUTION
-- =====================================================

-- 10. GENERATE 350 TRIPS (25 ROUTES x 14 DAYS)

WITH active_buses AS (
    SELECT bus_id,
           ROW_NUMBER() OVER (ORDER BY bus_id) AS rn
    FROM buses
    WHERE status = 'ACTIVE'
),
available_drivers AS (
    SELECT driver_id,
           ROW_NUMBER() OVER (ORDER BY driver_id) AS rn
    FROM drivers
    WHERE status = 'AVAILABLE'
),
trip_dates AS (
    SELECT
        s.schedule_id,
        s.route_id,
        r.route_number,
        r.estimated_duration_minutes,
        s.departure_time,
        gs.service_date::DATE AS service_date
    FROM schedules s
    JOIN routes r ON r.route_id = s.route_id
    CROSS JOIN generate_series(
        CURRENT_DATE - 13,
        CURRENT_DATE,
        INTERVAL '1 day'
    ) AS gs(service_date)
    JOIN schedule_operating_days sod
        ON sod.schedule_id = s.schedule_id
    JOIN operating_days od
        ON od.day_id = sod.day_id
       AND od.day_id = EXTRACT(ISODOW FROM gs.service_date)::SMALLINT
)
INSERT INTO trips (
    schedule_id,
    route_id,
    bus_id,
    driver_id,
    service_date,
    scheduled_start,
    actual_start,
    actual_end,
    trip_status
)
SELECT
    td.schedule_id,
    td.route_id,
    ab.bus_id,
    ad.driver_id,
    td.service_date,

    (td.service_date + td.departure_time)::TIMESTAMPTZ,

    (td.service_date + td.departure_time)::TIMESTAMPTZ
        + (FLOOR(RANDOM() * 6)::INTEGER * INTERVAL '1 minute'),

    (td.service_date + td.departure_time)::TIMESTAMPTZ
        + ((td.estimated_duration_minutes
            + FLOOR(RANDOM() * 16)::INTEGER) * INTERVAL '1 minute'),

    'COMPLETED'

FROM trip_dates td
JOIN active_buses ab
    ON ab.rn = SUBSTRING(td.route_number FROM 2)::INTEGER
JOIN available_drivers ad
    ON ad.rn = SUBSTRING(td.route_number FROM 2)::INTEGER;


-- 11. GENERATE ACTUAL STOP LOGS
-- Every trip visits all 10 stops on its route.


-- 11. GENERATE ACTUAL STOP LOGS
-- Corrected version

INSERT INTO trip_stop_logs (
    trip_id,
    route_id,
    route_stop_id,
    scheduled_arrival_at,
    actual_arrival_at,
    actual_departure_at,
    stop_status
)

SELECT
    t.trip_id,
    t.route_id,
    sst.route_stop_id,

    scheduled.scheduled_arrival_at,

    actual.actual_arrival_at,

    actual.actual_arrival_at + INTERVAL '3 minutes',

    'REACHED'

FROM trips t

JOIN schedule_stop_times sst
    ON sst.schedule_id = t.schedule_id
   AND sst.route_id = t.route_id

CROSS JOIN LATERAL (
    SELECT
        (
            t.service_date + sst.scheduled_arrival
        )::TIMESTAMPTZ AS scheduled_arrival_at
) scheduled

CROSS JOIN LATERAL (
    SELECT
        scheduled.scheduled_arrival_at
        + (
            FLOOR(RANDOM() * 901)::INTEGER
            * INTERVAL '1 second'
        ) AS actual_arrival_at
) actual;


-- =====================================================
-- END OF PART C
-- =====================================================


-- =====================================================
-- PART D: PASSENGER ANALYTICS AND DELAYS
-- =====================================================

-- 12. GENERATE PASSENGER COUNT RECORDS

INSERT INTO passenger_counts (
    trip_stop_log_id,
    boarding_count,
    alighting_count,
    recorded_at
)
SELECT
    tsl.trip_stop_log_id,

    5 + FLOOR(RANDOM() * 11)::INTEGER,

    FLOOR(RANDOM() * 6)::INTEGER,

    tsl.actual_arrival_at

FROM trip_stop_logs tsl;


-- 13. GENERATE DELAY RECORDS
-- Only records delays exceeding 5 minutes.

WITH ranked_reasons AS (
    SELECT
        reason_id,
        ROW_NUMBER() OVER (ORDER BY reason_id) AS rn,
        COUNT(*) OVER () AS total_reasons
    FROM delay_reasons
),
delayed_stops AS (
    SELECT
        trip_stop_log_id,
        EXTRACT(
            EPOCH FROM (actual_arrival_at - scheduled_arrival_at)
        )::INTEGER AS delay_seconds
    FROM trip_stop_logs
    WHERE actual_arrival_at >
          scheduled_arrival_at + INTERVAL '5 minutes'
)
INSERT INTO delay_records (
    trip_stop_log_id,
    reason_id,
    delay_seconds,
    severity,
    remarks
)
SELECT
    ds.trip_stop_log_id,
    rr.reason_id,
    ds.delay_seconds,

    CASE
        WHEN ds.delay_seconds > 600 THEN 'SEVERE'
        WHEN ds.delay_seconds > 300 THEN 'MODERATE'
        ELSE 'MINOR'
    END,

    'Automatically generated sample delay record'

FROM delayed_stops ds
JOIN ranked_reasons rr
    ON rr.rn =
       ((ds.trip_stop_log_id - 1) % rr.total_reasons) + 1;


-- =====================================================
-- COMPLETE DATA GENERATION
-- =====================================================

COMMIT;


SELECT
    (SELECT COUNT(*) FROM buses) AS buses,
    (SELECT COUNT(*) FROM drivers) AS drivers,
    (SELECT COUNT(*) FROM trips) AS trips,
    (SELECT COUNT(*) FROM trip_stop_logs) AS stop_logs,
    (SELECT COUNT(*) FROM passenger_counts) AS passengers;

	SELECT 'Buses' AS entity, COUNT(*) AS total FROM buses
UNION ALL
SELECT 'Drivers', COUNT(*) FROM drivers
UNION ALL
SELECT 'Routes', COUNT(*) FROM routes
UNION ALL
SELECT 'Stops', COUNT(*) FROM stops
UNION ALL
SELECT 'Trips', COUNT(*) FROM trips
UNION ALL
SELECT 'Trip Stop Logs', COUNT(*) FROM trip_stop_logs
UNION ALL
SELECT 'Passenger Records', COUNT(*) FROM passenger_counts
UNION ALL
SELECT 'Delay Records', COUNT(*) FROM delay_records;