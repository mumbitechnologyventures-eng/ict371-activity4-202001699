# ICT371 Activity 4 – PostgreSQL Scenario Assignment

**Student:** Chibesa Mumbi  
**Student No:** 202001699  
**Course:** ICT371 Advanced Database – Mulungushi University  
**Due:** 5 October 2026, 23:59

PL/pgSQL solutions for four of the six scenarios. Each file covers all nine steps:
tables and sample data, IF/ELSIF/ELSE, WHILE and numeric FOR loops, a stored procedure that takes stock or capacity,
valid and over-limit calls, a procedure that releases stock and is safe to call twice, an explicit cursor,
EXCEPTION handling for invalid input, and final queries.

| File | Scenario |
|---|---|
| `scenario_1_202001699.sql` | 1 – University Library Book Loans |
| `scenario_2_202001699.sql` | 2 – Computer Laboratory Reservations |
| `scenario_5_202001699.sql` | 5 – Engineering Workshop Tool Loans |
| `scenario_6_202001699.sql` | 6 – University Event Seat Booking |

## How to run

1. Open pgAdmin 4 and connect to the PostgreSQL server (tested on PostgreSQL 18).
2. Open the Query Tool on the `postgres` database.
3. Open a scenario file and press **F5**.
4. The final tables appear in **Data Output**. The `RAISE NOTICE` output from each step appears in **Messages**.

Each script drops and recreates its own tables and procedures, so it can be run again safely.
