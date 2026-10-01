-- =====================================================================
-- ICT371 PostgreSQL Scenario Assignment (Activity 4)
-- Scenario 6: University Event Seat Booking
-- Student: Chibesa Mumbi | Student No: 202001699
-- Run the whole file in the pgAdmin Query Tool (F5).
-- Messages from RAISE NOTICE appear in the "Messages" tab.
-- =====================================================================

-- Clean start so the script can be re-run
DROP PROCEDURE IF EXISTS book_seats(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS cancel_booking(INT);
DROP TABLE IF EXISTS bookings;
DROP TABLE IF EXISTS events;

-- ---------------------------------------------------------------------
-- 1. Tables and sample data
-- ---------------------------------------------------------------------
CREATE TABLE events (
    event_id        SERIAL PRIMARY KEY,
    event_name      VARCHAR(100) NOT NULL,
    venue           VARCHAR(100) NOT NULL,
    event_date      DATE NOT NULL,
    total_seats     INT NOT NULL CHECK (total_seats > 0),
    available_seats INT NOT NULL CHECK (available_seats >= 0)
);

CREATE TABLE bookings (
    booking_id     SERIAL PRIMARY KEY,
    event_id       INT NOT NULL REFERENCES events(event_id),
    student_number VARCHAR(20) NOT NULL,
    seats          INT NOT NULL CHECK (seats > 0),
    status         VARCHAR(20) NOT NULL DEFAULT 'BOOKED',
    booked_on      TIMESTAMP NOT NULL DEFAULT NOW(),
    cancelled_on   TIMESTAMP
);

INSERT INTO events (event_name, venue, event_date, total_seats, available_seats) VALUES
    ('ICT Innovation Expo',    'Great Hall',      '2026-10-15', 200, 200),
    ('Career Fair Talk',       'Lecture Theatre', '2026-10-17', 120, 8),
    ('Graduation Rehearsal',   'Main Auditorium', '2026-10-20', 300, 0),
    ('Cultural Night',         'Great Hall',      '2026-10-24', 150, 60);

SELECT * FROM events ORDER BY event_id;

-- ---------------------------------------------------------------------
-- 2. IF / ELSIF / ELSE - seat status of one event
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_name  events.event_name%TYPE;
    v_seats events.available_seats%TYPE;
BEGIN
    SELECT event_name, available_seats INTO v_name, v_seats
    FROM events WHERE event_id = 2;

    IF v_seats = 0 THEN
        RAISE NOTICE '% is FULL.', v_name;
    ELSIF v_seats <= 10 THEN
        RAISE NOTICE '% is NEARLY FULL (% seats left).', v_name, v_seats;
    ELSE
        RAISE NOTICE '% has PLENTY OF SEATS (% available).', v_name, v_seats;
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- 3. WHILE loop (booking reminder days) and numeric FOR loop (entrance checks)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    i INT := 1;
BEGIN
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Booking reminder day %', i;
        i := i + 1;
    END LOOP;

    FOR gate IN 1..3 LOOP
        RAISE NOTICE 'Entrance check number %', gate;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 4. book_seats procedure
--    Invalid quantity (<= 0) raises an exception (handled in step 8).
--    Not enough seats -> notice only, nothing is recorded.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE book_seats(
    p_event_id       INT,
    p_student_number VARCHAR,
    p_seats          INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available events.available_seats%TYPE;
BEGIN
    IF p_seats IS NULL OR p_seats <= 0 THEN
        RAISE EXCEPTION 'Invalid number of seats: %. Must be greater than zero.', p_seats;
    END IF;

    SELECT available_seats INTO v_available
    FROM events WHERE event_id = p_event_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Event % does not exist. Booking not recorded.', p_event_id;
        RETURN;
    END IF;

    IF p_seats > v_available THEN
        RAISE NOTICE 'Booking refused for %: requested % seats, only % remaining for event %.',
                     p_student_number, p_seats, v_available, p_event_id;
        RETURN;
    END IF;

    UPDATE events
    SET available_seats = available_seats - p_seats
    WHERE event_id = p_event_id;

    INSERT INTO bookings (event_id, student_number, seats)
    VALUES (p_event_id, p_student_number, p_seats);

    RAISE NOTICE 'Booking recorded: student % booked % seat(s) for event %.',
                 p_student_number, p_seats, p_event_id;
END;
$$;

-- ---------------------------------------------------------------------
-- 5. Two valid bookings and one request exceeding remaining seats
-- ---------------------------------------------------------------------
CALL book_seats(1, '202001699', 3);    -- valid
CALL book_seats(4, '202106674', 2);    -- valid
CALL book_seats(2, '202209915', 12);   -- exceeds (only 8 remaining)

SELECT * FROM events ORDER BY event_id;
SELECT * FROM bookings ORDER BY booking_id;

-- ---------------------------------------------------------------------
-- 6. cancel_booking procedure - called twice for the same booking
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE cancel_booking(p_booking_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_id bookings.event_id%TYPE;
    v_seats    bookings.seats%TYPE;
    v_status   bookings.status%TYPE;
BEGIN
    SELECT event_id, seats, status
    INTO v_event_id, v_seats, v_status
    FROM bookings WHERE booking_id = p_booking_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Booking % does not exist.', p_booking_id;
        RETURN;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Booking % is already cancelled. Seats NOT released again.', p_booking_id;
        RETURN;
    END IF;

    UPDATE bookings
    SET status = 'CANCELLED', cancelled_on = NOW()
    WHERE booking_id = p_booking_id;

    UPDATE events
    SET available_seats = available_seats + v_seats
    WHERE event_id = v_event_id;

    RAISE NOTICE 'Booking % cancelled. % seat(s) released to event %.',
                 p_booking_id, v_seats, v_event_id;
END;
$$;

CALL cancel_booking(1);   -- first call: releases 3 seats
CALL cancel_booking(1);   -- second call: no change

SELECT * FROM events ORDER BY event_id;
SELECT * FROM bookings ORDER BY booking_id;

-- ---------------------------------------------------------------------
-- 7. Explicit cursor - full or nearly full events (<= 10 seats left)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    full_cur CURSOR (p_limit INT) FOR
        SELECT event_id, event_name, event_date, available_seats
        FROM events
        WHERE available_seats <= p_limit
        ORDER BY available_seats;
    rec RECORD;
BEGIN
    RAISE NOTICE 'Full or nearly full events (10 or fewer seats left):';
    OPEN full_cur(10);
    LOOP
        FETCH full_cur INTO rec;
        EXIT WHEN NOT FOUND;
        IF rec.available_seats = 0 THEN
            RAISE NOTICE '  Event % - % on % : FULL', rec.event_id, rec.event_name, rec.event_date;
        ELSE
            RAISE NOTICE '  Event % - % on % : % seats left',
                         rec.event_id, rec.event_name, rec.event_date, rec.available_seats;
        END IF;
    END LOOP;
    CLOSE full_cur;
END $$;

-- ---------------------------------------------------------------------
-- 8. Book zero seats - handled with an EXCEPTION block
-- ---------------------------------------------------------------------
DO $$
BEGIN
    CALL book_seats(1, '202001699', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- 9. Final seat availability and booking statuses
-- ---------------------------------------------------------------------
SELECT event_id, event_name, venue, event_date, total_seats, available_seats
FROM events ORDER BY event_id;

SELECT b.booking_id, b.student_number, e.event_name, b.seats,
       b.status, b.booked_on, b.cancelled_on
FROM bookings b
JOIN events e ON e.event_id = b.event_id
ORDER BY b.booking_id;
