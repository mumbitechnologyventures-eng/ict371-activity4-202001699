-- =====================================================================
-- ICT371 PostgreSQL Scenario Assignment (Activity 4)
-- Scenario 2: Computer Laboratory Reservations
-- Student: Chibesa Mumbi | Student No: 202001699
-- Run the whole file in the pgAdmin Query Tool (F5).
-- Messages from RAISE NOTICE appear in the "Messages" tab.
-- =====================================================================

-- Clean start so the script can be re-run
DROP PROCEDURE IF EXISTS reserve_workstations(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS cancel_reservation(INT);
DROP TABLE IF EXISTS reservations;
DROP TABLE IF EXISTS lab_sessions;

-- ---------------------------------------------------------------------
-- 1. Tables and sample data
-- ---------------------------------------------------------------------
CREATE TABLE lab_sessions (
    session_id             SERIAL PRIMARY KEY,
    lab_name               VARCHAR(50) NOT NULL,
    session_date           DATE NOT NULL,
    start_time             TIME NOT NULL,
    total_workstations     INT NOT NULL CHECK (total_workstations > 0),
    available_workstations INT NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id   SERIAL PRIMARY KEY,
    session_id       INT NOT NULL REFERENCES lab_sessions(session_id),
    lecturer         VARCHAR(100) NOT NULL,
    workstations     INT NOT NULL CHECK (workstations > 0),
    status           VARCHAR(20) NOT NULL DEFAULT 'RESERVED',
    reserved_on      TIMESTAMP NOT NULL DEFAULT NOW(),
    cancelled_on     TIMESTAMP
);

INSERT INTO lab_sessions (lab_name, session_date, start_time, total_workstations, available_workstations) VALUES
    ('Lab A', '2026-10-06', '08:00', 40, 40),
    ('Lab B', '2026-10-06', '10:00', 30, 4),
    ('Lab C', '2026-10-07', '14:00', 25, 0),
    ('Lab A', '2026-10-08', '09:00', 40, 20);

SELECT * FROM lab_sessions ORDER BY session_id;

-- ---------------------------------------------------------------------
-- 2. IF / ELSIF / ELSE - capacity of one session
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_lab       lab_sessions.lab_name%TYPE;
    v_available lab_sessions.available_workstations%TYPE;
BEGIN
    SELECT lab_name, available_workstations INTO v_lab, v_available
    FROM lab_sessions WHERE session_id = 2;

    IF v_available = 0 THEN
        RAISE NOTICE 'Session 2 (%) is FULL.', v_lab;
    ELSIF v_available <= 5 THEN
        RAISE NOTICE 'Session 2 (%) is NEARLY FULL (% workstations left).', v_lab, v_available;
    ELSE
        RAISE NOTICE 'Session 2 (%) has ENOUGH workstations (% free).', v_lab, v_available;
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- 3. WHILE loop (preparation reminders) and numeric FOR loop (checks)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    i INT := 1;
BEGIN
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', i;
        i := i + 1;
    END LOOP;

    FOR ws IN 1..3 LOOP
        RAISE NOTICE 'Workstation check number %', ws;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 4. reserve_workstations procedure
--    Invalid quantity (<= 0) raises an exception (handled in step 8).
--    Not enough capacity -> notice only, nothing is recorded.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE reserve_workstations(
    p_session_id   INT,
    p_lecturer     VARCHAR,
    p_workstations INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available lab_sessions.available_workstations%TYPE;
BEGIN
    IF p_workstations IS NULL OR p_workstations <= 0 THEN
        RAISE EXCEPTION 'Invalid number of workstations: %. Must be greater than zero.', p_workstations;
    END IF;

    SELECT available_workstations INTO v_available
    FROM lab_sessions WHERE session_id = p_session_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Session % does not exist. Reservation not recorded.', p_session_id;
        RETURN;
    END IF;

    IF p_workstations > v_available THEN
        RAISE NOTICE 'Reservation refused for %: requested %, only % available in session %.',
                     p_lecturer, p_workstations, v_available, p_session_id;
        RETURN;
    END IF;

    UPDATE lab_sessions
    SET available_workstations = available_workstations - p_workstations
    WHERE session_id = p_session_id;

    INSERT INTO reservations (session_id, lecturer, workstations)
    VALUES (p_session_id, p_lecturer, p_workstations);

    RAISE NOTICE 'Reservation recorded: % reserved % workstations in session %.',
                 p_lecturer, p_workstations, p_session_id;
END;
$$;

-- ---------------------------------------------------------------------
-- 5. Two valid reservations and one request exceeding capacity
-- ---------------------------------------------------------------------
CALL reserve_workstations(1, 'Dr. Banda',  35);   -- valid
CALL reserve_workstations(4, 'Mr. Phiri',  15);   -- valid
CALL reserve_workstations(2, 'Ms. Mwansa', 10);   -- exceeds (only 4 available)

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- ---------------------------------------------------------------------
-- 6. cancel_reservation procedure - called twice for the same reservation
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id   reservations.session_id%TYPE;
    v_workstations reservations.workstations%TYPE;
    v_status       reservations.status%TYPE;
BEGIN
    SELECT session_id, workstations, status
    INTO v_session_id, v_workstations, v_status
    FROM reservations WHERE reservation_id = p_reservation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Reservation % does not exist.', p_reservation_id;
        RETURN;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % is already cancelled. Workstations NOT released again.', p_reservation_id;
        RETURN;
    END IF;

    UPDATE reservations
    SET status = 'CANCELLED', cancelled_on = NOW()
    WHERE reservation_id = p_reservation_id;

    UPDATE lab_sessions
    SET available_workstations = available_workstations + v_workstations
    WHERE session_id = v_session_id;

    RAISE NOTICE 'Reservation % cancelled. % workstations released to session %.',
                 p_reservation_id, v_workstations, v_session_id;
END;
$$;

CALL cancel_reservation(1);   -- first call: releases 35 workstations
CALL cancel_reservation(1);   -- second call: no change

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- ---------------------------------------------------------------------
-- 7. Explicit cursor - sessions with few workstations remaining (<= 5)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    low_cur CURSOR (p_limit INT) FOR
        SELECT session_id, lab_name, session_date, available_workstations
        FROM lab_sessions
        WHERE available_workstations <= p_limit
        ORDER BY available_workstations;
    rec RECORD;
BEGIN
    RAISE NOTICE 'Sessions with 5 or fewer workstations remaining:';
    OPEN low_cur(5);
    LOOP
        FETCH low_cur INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE '  Session % - % on % : % free',
                     rec.session_id, rec.lab_name, rec.session_date, rec.available_workstations;
    END LOOP;
    CLOSE low_cur;
END $$;

-- ---------------------------------------------------------------------
-- 8. Request zero workstations - handled with an EXCEPTION block
-- ---------------------------------------------------------------------
DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr. Banda', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- 9. Final workstation availability and reservation statuses
-- ---------------------------------------------------------------------
SELECT session_id, lab_name, session_date, start_time,
       total_workstations, available_workstations
FROM lab_sessions ORDER BY session_id;

SELECT r.reservation_id, r.lecturer, s.lab_name, s.session_date,
       r.workstations, r.status, r.reserved_on, r.cancelled_on
FROM reservations r
JOIN lab_sessions s ON s.session_id = r.session_id
ORDER BY r.reservation_id;
