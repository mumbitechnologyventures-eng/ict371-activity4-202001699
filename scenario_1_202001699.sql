-- =====================================================================
-- ICT371 PostgreSQL Scenario Assignment (Activity 4)
-- Scenario 1: University Library Book Loans
-- Student: Chibesa Mumbi | Student No: 202001699
-- Run the whole file in the pgAdmin Query Tool (F5).
-- Messages from RAISE NOTICE appear in the "Messages" tab.
-- =====================================================================

-- Clean start so the script can be re-run
DROP PROCEDURE IF EXISTS borrow_book(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS return_book(INT);
DROP TABLE IF EXISTS book_loans;
DROP TABLE IF EXISTS books;

-- ---------------------------------------------------------------------
-- 1. Tables and sample data
-- ---------------------------------------------------------------------
CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(100) NOT NULL,
    author           VARCHAR(100) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id        SERIAL PRIMARY KEY,
    book_id        INT NOT NULL REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    loan_status    VARCHAR(20) NOT NULL DEFAULT 'BORROWED',
    loan_date      DATE NOT NULL DEFAULT CURRENT_DATE,
    return_date    DATE
);

INSERT INTO books (title, author, available_copies) VALUES
    ('Database System Concepts',      'Silberschatz', 6),
    ('Introduction to Algorithms',    'Cormen',       2),
    ('Computer Networks',             'Tanenbaum',    0),
    ('Operating System Concepts',     'Galvin',       4);

SELECT * FROM books ORDER BY book_id;

-- ---------------------------------------------------------------------
-- 2. IF / ELSIF / ELSE - stock level of one book
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_title  books.title%TYPE;
    v_copies books.available_copies%TYPE;
BEGIN
    SELECT title, available_copies INTO v_title, v_copies
    FROM books WHERE book_id = 2;

    IF v_copies = 0 THEN
        RAISE NOTICE '"%" is UNAVAILABLE (0 copies).', v_title;
    ELSIF v_copies <= 2 THEN
        RAISE NOTICE '"%" is LOW on copies (% left).', v_title, v_copies;
    ELSE
        RAISE NOTICE '"%" is SUFFICIENTLY STOCKED (% copies).', v_title, v_copies;
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- 3. WHILE loop (overdue reminders) and numeric FOR loop (shelf numbers)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    i INT := 1;
BEGIN
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number %', i;
        i := i + 1;
    END LOOP;

    FOR shelf IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number %', shelf;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 4. borrow_book procedure
--    Invalid quantity (<= 0) raises an exception (handled in step 8).
--    Not enough copies -> notice only, nothing is recorded.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE borrow_book(
    p_book_id        INT,
    p_student_number VARCHAR,
    p_quantity       INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available books.available_copies%TYPE;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: %. Quantity must be greater than zero.', p_quantity;
    END IF;

    SELECT available_copies INTO v_available
    FROM books WHERE book_id = p_book_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Book % does not exist. Loan not recorded.', p_book_id;
        RETURN;
    END IF;

    IF p_quantity > v_available THEN
        RAISE NOTICE 'Loan refused for %: requested %, only % available for book %.',
                     p_student_number, p_quantity, v_available, p_book_id;
        RETURN;
    END IF;

    UPDATE books
    SET available_copies = available_copies - p_quantity
    WHERE book_id = p_book_id;

    INSERT INTO book_loans (book_id, student_number, quantity)
    VALUES (p_book_id, p_student_number, p_quantity);

    RAISE NOTICE 'Loan recorded: student % borrowed % copy/copies of book %.',
                 p_student_number, p_quantity, p_book_id;
END;
$$;

-- ---------------------------------------------------------------------
-- 5. Two valid loans and one request exceeding available copies
-- ---------------------------------------------------------------------
CALL borrow_book(1, '202001699', 2);   -- valid
CALL borrow_book(4, '202104512', 1);   -- valid
CALL borrow_book(2, '202203317', 5);   -- exceeds (only 2 available)

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- ---------------------------------------------------------------------
-- 6. return_book procedure - called twice for the same loan
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id  book_loans.book_id%TYPE;
    v_quantity book_loans.quantity%TYPE;
    v_status   book_loans.loan_status%TYPE;
BEGIN
    SELECT book_id, quantity, loan_status
    INTO v_book_id, v_quantity, v_status
    FROM book_loans WHERE loan_id = p_loan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Loan % does not exist.', p_loan_id;
        RETURN;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % was already returned. Copies NOT restored again.', p_loan_id;
        RETURN;
    END IF;

    UPDATE book_loans
    SET loan_status = 'RETURNED', return_date = CURRENT_DATE
    WHERE loan_id = p_loan_id;

    UPDATE books
    SET available_copies = available_copies + v_quantity
    WHERE book_id = v_book_id;

    RAISE NOTICE 'Loan % returned. % copy/copies restored to book %.',
                 p_loan_id, v_quantity, v_book_id;
END;
$$;

CALL return_book(1);   -- first call: restores 2 copies of book 1
CALL return_book(1);   -- second call: no change

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- ---------------------------------------------------------------------
-- 7. Explicit cursor - books with few copies remaining (<= 2)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    low_cur CURSOR (p_limit INT) FOR
        SELECT book_id, title, available_copies
        FROM books
        WHERE available_copies <= p_limit
        ORDER BY available_copies;
    rec RECORD;
BEGIN
    RAISE NOTICE 'Books with 2 or fewer copies remaining:';
    OPEN low_cur(2);
    LOOP
        FETCH low_cur INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE '  Book % - "%" : % copies', rec.book_id, rec.title, rec.available_copies;
    END LOOP;
    CLOSE low_cur;
END $$;

-- ---------------------------------------------------------------------
-- 8. Borrow zero copies - handled with an EXCEPTION block
-- ---------------------------------------------------------------------
DO $$
BEGIN
    CALL borrow_book(1, '202001699', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- 9. Final quantities and loan statuses
-- ---------------------------------------------------------------------
SELECT book_id, title, available_copies FROM books ORDER BY book_id;

SELECT l.loan_id, l.student_number, b.title, l.quantity,
       l.loan_status, l.loan_date, l.return_date
FROM book_loans l
JOIN books b ON b.book_id = l.book_id
ORDER BY l.loan_id;
