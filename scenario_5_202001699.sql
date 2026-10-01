-- =====================================================================
-- ICT371 PostgreSQL Scenario Assignment (Activity 4)
-- Scenario 5: Engineering Workshop Tool Loans
-- Student: Chibesa Mumbi | Student No: 202001699
-- Run the whole file in the pgAdmin Query Tool (F5).
-- Messages from RAISE NOTICE appear in the "Messages" tab.
-- =====================================================================

-- Clean start so the script can be re-run
DROP PROCEDURE IF EXISTS issue_tool(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS return_tool(INT);
DROP TABLE IF EXISTS tool_loans;
DROP TABLE IF EXISTS tools;

-- ---------------------------------------------------------------------
-- 1. Tables and sample data
-- ---------------------------------------------------------------------
CREATE TABLE tools (
    tool_id            SERIAL PRIMARY KEY,
    tool_name          VARCHAR(100) NOT NULL,
    available_quantity INT NOT NULL CHECK (available_quantity >= 0)
);

CREATE TABLE tool_loans (
    loan_id        SERIAL PRIMARY KEY,
    tool_id        INT NOT NULL REFERENCES tools(tool_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    status         VARCHAR(20) NOT NULL DEFAULT 'ISSUED',
    issued_on      DATE NOT NULL DEFAULT CURRENT_DATE,
    returned_on    DATE
);

INSERT INTO tools (tool_name, available_quantity) VALUES
    ('Digital Multimeter',   10),
    ('Soldering Iron',        3),
    ('Oscilloscope',          0),
    ('Vernier Caliper',       8);

SELECT * FROM tools ORDER BY tool_id;

-- ---------------------------------------------------------------------
-- 2. IF / ELSIF / ELSE - availability of one tool
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_name tools.tool_name%TYPE;
    v_qty  tools.available_quantity%TYPE;
BEGIN
    SELECT tool_name, available_quantity INTO v_name, v_qty
    FROM tools WHERE tool_id = 2;

    IF v_qty = 0 THEN
        RAISE NOTICE '% is UNAVAILABLE (0 in stock).', v_name;
    ELSIF v_qty <= 3 THEN
        RAISE NOTICE '% is LOW on stock (% left).', v_name, v_qty;
    ELSE
        RAISE NOTICE '% is READILY AVAILABLE (% in stock).', v_name, v_qty;
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- 3. WHILE loop (safety reminders) and numeric FOR loop (inspections)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    i INT := 1;
BEGIN
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Workshop safety reminder %', i;
        i := i + 1;
    END LOOP;

    FOR insp IN 1..3 LOOP
        RAISE NOTICE 'Tool inspection number %', insp;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 4. issue_tool procedure
--    Invalid quantity (<= 0) raises an exception (handled in step 8).
--    Not enough stock -> notice only, nothing is recorded.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE issue_tool(
    p_tool_id        INT,
    p_student_number VARCHAR,
    p_quantity       INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available tools.available_quantity%TYPE;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: %. Quantity must be greater than zero.', p_quantity;
    END IF;

    SELECT available_quantity INTO v_available
    FROM tools WHERE tool_id = p_tool_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Tool % does not exist. Loan not recorded.', p_tool_id;
        RETURN;
    END IF;

    IF p_quantity > v_available THEN
        RAISE NOTICE 'Loan refused for %: requested %, only % available for tool %.',
                     p_student_number, p_quantity, v_available, p_tool_id;
        RETURN;
    END IF;

    UPDATE tools
    SET available_quantity = available_quantity - p_quantity
    WHERE tool_id = p_tool_id;

    INSERT INTO tool_loans (tool_id, student_number, quantity)
    VALUES (p_tool_id, p_student_number, p_quantity);

    RAISE NOTICE 'Loan recorded: student % was issued % of tool %.',
                 p_student_number, p_quantity, p_tool_id;
END;
$$;

-- ---------------------------------------------------------------------
-- 5. Two valid loans and one request exceeding stock
-- ---------------------------------------------------------------------
CALL issue_tool(1, '202001699', 4);   -- valid
CALL issue_tool(4, '202105230', 2);   -- valid
CALL issue_tool(2, '202208841', 6);   -- exceeds (only 3 available)

SELECT * FROM tools ORDER BY tool_id;
SELECT * FROM tool_loans ORDER BY loan_id;

-- ---------------------------------------------------------------------
-- 6. return_tool procedure - called twice for the same loan
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE return_tool(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_tool_id  tool_loans.tool_id%TYPE;
    v_quantity tool_loans.quantity%TYPE;
    v_status   tool_loans.status%TYPE;
BEGIN
    SELECT tool_id, quantity, status
    INTO v_tool_id, v_quantity, v_status
    FROM tool_loans WHERE loan_id = p_loan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Loan % does not exist.', p_loan_id;
        RETURN;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % was already returned. Stock NOT increased again.', p_loan_id;
        RETURN;
    END IF;

    UPDATE tool_loans
    SET status = 'RETURNED', returned_on = CURRENT_DATE
    WHERE loan_id = p_loan_id;

    UPDATE tools
    SET available_quantity = available_quantity + v_quantity
    WHERE tool_id = v_tool_id;

    RAISE NOTICE 'Loan % returned. % added back to tool %.',
                 p_loan_id, v_quantity, v_tool_id;
END;
$$;

CALL return_tool(1);   -- first call: restores 4 multimeters
CALL return_tool(1);   -- second call: no change

SELECT * FROM tools ORDER BY tool_id;
SELECT * FROM tool_loans ORDER BY loan_id;

-- ---------------------------------------------------------------------
-- 7. Explicit cursor - tools with low availability (<= 3)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    low_cur CURSOR (p_limit INT) FOR
        SELECT tool_id, tool_name, available_quantity
        FROM tools
        WHERE available_quantity <= p_limit
        ORDER BY available_quantity;
    rec RECORD;
BEGIN
    RAISE NOTICE 'Tools with 3 or fewer available:';
    OPEN low_cur(3);
    LOOP
        FETCH low_cur INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE '  Tool % - % : % available', rec.tool_id, rec.tool_name, rec.available_quantity;
    END LOOP;
    CLOSE low_cur;
END $$;

-- ---------------------------------------------------------------------
-- 8. Issue zero tools - handled with an EXCEPTION block
-- ---------------------------------------------------------------------
DO $$
BEGIN
    CALL issue_tool(1, '202001699', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- 9. Final tool quantities and loan statuses
-- ---------------------------------------------------------------------
SELECT tool_id, tool_name, available_quantity FROM tools ORDER BY tool_id;

SELECT l.loan_id, l.student_number, t.tool_name, l.quantity,
       l.status, l.issued_on, l.returned_on
FROM tool_loans l
JOIN tools t ON t.tool_id = l.tool_id
ORDER BY l.loan_id;
