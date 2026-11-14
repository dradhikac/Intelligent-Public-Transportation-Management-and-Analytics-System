
-- ==========================================
-- TransitIQ: Initial Lookup Data
-- ==========================================

-- BUS TYPES
INSERT INTO bus_types
(type_name, description, seating_capacity, standing_capacity)
VALUES
('AC', 'Air Conditioned City Bus', 40, 20),
('NON_AC', 'Non Air Conditioned City Bus', 45, 25),
('ELECTRIC', 'Electric City Bus', 35, 20),
('MINI', 'Mini City Bus', 20, 5)
ON CONFLICT (type_name) DO NOTHING;


-- OPERATING DAYS
INSERT INTO operating_days (day_id, day_name)
VALUES
(1, 'Monday'),
(2, 'Tuesday'),
(3, 'Wednesday'),
(4, 'Thursday'),
(5, 'Friday'),
(6, 'Saturday'),
(7, 'Sunday')
ON CONFLICT (day_id) DO NOTHING;


-- DELAY REASONS
INSERT INTO delay_reasons (reason_name, description)
VALUES
('Traffic Congestion', 'Heavy traffic on the road'),
('Vehicle Breakdown', 'Mechanical or technical failure'),
('Weather Conditions', 'Rain or adverse weather'),
('Road Construction', 'Road repair or construction'),
('Passenger Delay', 'Extended passenger boarding time'),
('Driver Availability', 'Driver-related operational issues'),
('Accident', 'Road accident causing delay'),
('Other', 'Other operational reasons')
ON CONFLICT (reason_name) DO NOTHING;

