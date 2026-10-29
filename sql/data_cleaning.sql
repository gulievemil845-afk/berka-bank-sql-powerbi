USE berka_bank;

SELECT * FROM district LIMIT 5;

-- Step 1: Rename district columns (A1..A16 -> meaningful names)
ALTER TABLE district
    RENAME COLUMN A1  TO district_id,
    RENAME COLUMN A2  TO district_name,
    RENAME COLUMN A3  TO region,
    RENAME COLUMN A4  TO inhabitants,
    RENAME COLUMN A5  TO municipalities_lt_499,
    RENAME COLUMN A6  TO municipalities_500_1999,
    RENAME COLUMN A7  TO municipalities_2000_9999,
    RENAME COLUMN A8  TO municipalities_gt_10000,
    RENAME COLUMN A9  TO cities,
    RENAME COLUMN A10 TO urban_ratio,
    RENAME COLUMN A11 TO avg_salary,
    RENAME COLUMN A12 TO unemployment_rate_95,
    RENAME COLUMN A13 TO unemployment_rate_96,
    RENAME COLUMN A14 TO entrepreneurs_per_1000,
    RENAME COLUMN A15 TO crimes_95,
    RENAME COLUMN A16 TO crimes_96;


-- Step 2: Primary keys
ALTER TABLE district MODIFY district_id INT NOT NULL, ADD PRIMARY KEY (district_id);
ALTER TABLE account  MODIFY account_id  INT NOT NULL, ADD PRIMARY KEY (account_id);
ALTER TABLE client   MODIFY client_id   INT NOT NULL, ADD PRIMARY KEY (client_id);
ALTER TABLE loan     MODIFY loan_id     INT NOT NULL, ADD PRIMARY KEY (loan_id);
ALTER TABLE disp     MODIFY disp_id     INT NOT NULL, ADD PRIMARY KEY (disp_id);
ALTER TABLE card     MODIFY card_id     INT NOT NULL, ADD PRIMARY KEY (card_id);
ALTER TABLE `order`  MODIFY order_id    INT NOT NULL, ADD PRIMARY KEY (order_id);


-- Step 3: Primary keys
-- Verification: every table should now have a primary key (expect 8 rows)
SELECT table_name, column_name
FROM information_schema.key_column_usage
WHERE table_schema = 'berka_bank'
  AND constraint_name = 'PRIMARY'
ORDER BY table_name;


-- Step 4:  Convert YYMMDD integers to real DATE columns
-- Why: dates are stored as integers (e.g. 930705), so date functions
--      like YEAR() and DATEDIFF() cannot be used.
-- Approach: add a new column, fill it, verify, then drop the old one.

-- 4a: loan
ALTER TABLE loan ADD COLUMN loan_date DATE;

UPDATE loan
SET loan_date = STR_TO_DATE(LPAD(`date`, 6, '0'), '%y%m%d')
WHERE loan_id > 0;

SELECT MIN(loan_date), MAX(loan_date), SUM(loan_date IS NULL) AS null_dates FROM loan;
ALTER TABLE loan DROP COLUMN `date`;


-- 4b: account
ALTER TABLE account ADD COLUMN account_date DATE;

UPDATE account
SET account_date = STR_TO_DATE(LPAD(`date`, 6, '0'), '%y%m%d')
WHERE account_id > 0;

SELECT MIN(account_date), MAX(account_date), SUM(account_date IS NULL) AS null_dates FROM account;
ALTER TABLE account DROP COLUMN `date`;


DESCRIBE loan;
DESCRIBE account;



-- Step 5: Fix data types (loan, account)
-- Why: the import wizard guessed types automatically.
--      Money must be DECIMAL (exact), codes should be short VARCHAR
-- =====================================================
-- 5a: Pre-check. Look at the values before changing the types,
--     so nothing unexpected (spaces, extra values) breaks the change.

-- Expected: status = A, B, C, D (length 1 each)
SELECT status, LENGTH(status) AS len, COUNT(*) AS cnt
FROM loan
GROUP BY status;

-- Expected: 3 values (POPLATEK MESICNE, POPLATEK TYDNE, POPLATEK PO OBRATU)
SELECT frequency, LENGTH(frequency) AS len, COUNT(*) AS cnt
FROM account
GROUP BY frequency;


-- 5b: Change the data types.
--     DECIMAL(12,2) stores money exactly with 2 decimals (DOUBLE can cause rounding errors).
ALTER TABLE loan
    MODIFY amount   DECIMAL(12,2),
    MODIFY payments DECIMAL(12,2),
    MODIFY status   VARCHAR(1);

ALTER TABLE account
    MODIFY frequency VARCHAR(30);


-- 5c: Verify the new structure
DESCRIBE loan;
DESCRIBE account;


-- =====================================================
-- Step 6: Decode client.birth_number into birth_date and gender
-- Why: birth_number is YYMMDD; for women 50 is added to the month.
--      One column hides two attributes we need for analysis.
-- Note: all clients were born in the 1900s, so we prepend '19'
--       (STR_TO_DATE with %y would read 11-69 as 2011-2069).
-- =====================================================

-- 6a: Pre-check. Month part should be 01-12 (men) or 51-62 (women).
SELECT MOD(birth_number DIV 100, 100) AS month_part, COUNT(*) AS cnt
FROM client
GROUP BY month_part
ORDER BY month_part;



WITH month_counts AS (
    SELECT MOD(birth_number DIV 100, 100) AS month_part, COUNT(*) AS cnt
    FROM client
    GROUP BY month_part
)
SELECT SUM(cnt) AS total_clients,
       SUM(CASE WHEN month_part > 12 THEN cnt ELSE 0 END) AS women,
       SUM(CASE WHEN month_part <= 12 THEN cnt ELSE 0 END) AS men
FROM month_counts;

-- Result: month part only in 01-12 and 51-62 (24 values), total 5,369 = all clients.
-- Split: 2,724 men (50.7%) / 2,645 women (49.3%).


-- 6b: Add the new columns
ALTER TABLE client
    ADD COLUMN gender     CHAR(1),
    ADD COLUMN birth_date DATE;

-- 6c: Fill the new columns
UPDATE client
SET gender = IF(MOD(birth_number DIV 100, 100) > 12, 'F', 'M'),
    birth_date = STR_TO_DATE(
        CONCAT(
            '19',
            LPAD(birth_number DIV 10000, 2, '0'),
            LPAD(IF(MOD(birth_number DIV 100, 100) > 12,
                    MOD(birth_number DIV 100, 100) - 50,
                    MOD(birth_number DIV 100, 100)), 2, '0'),
            LPAD(MOD(birth_number, 100), 2, '0')
        ), '%Y%m%d')
WHERE client_id > 0;


-- 6d: Verify (expect 2 rows, 0 NULL birth dates, birth years in the 1900s)
SELECT gender,
       COUNT(*)                AS clients,
       MIN(birth_date)         AS oldest,
       MAX(birth_date)         AS youngest,
       SUM(birth_date IS NULL) AS null_dates
FROM client
GROUP BY gender; 


-- =====================================================
-- Step 7: Standardize category values (Czech -> English)
-- Why: source values are in Czech (PRIJEM, VYDAJ...), which makes
--      dashboards unreadable for most audiences.
-- =====================================================

-- 7a: trans.type and trans.operation
--     type: PRIJEM = credit; VYDAJ and VYBER (cash withdrawal) are both money out, so merged into DEBIT.
--     operation: empty value = interest credited (all 183,114 rows have k_symbol = 'UROK', see Task 1).
UPDATE trans
SET type = CASE
        WHEN type = 'PRIJEM' THEN 'CREDIT'
        ELSE 'DEBIT'
    END,
    operation = CASE
        WHEN operation = 'VKLAD'          THEN 'Cash deposit'
        WHEN operation = 'VYBER'          THEN 'Cash withdrawal'
        WHEN operation = 'PREVOD Z UCTU'  THEN 'Incoming transfer'
        WHEN operation = 'PREVOD NA UCET' THEN 'Outgoing transfer'
        WHEN operation = 'VYBER KARTOU'   THEN 'Card withdrawal'
        WHEN operation = ''               THEN 'Interest'
        ELSE operation
    END
WHERE trans_id > 0;

-- 7b: account.frequency
UPDATE account
SET frequency = CASE
        WHEN frequency = 'POPLATEK MESICNE'   THEN 'Monthly'
        WHEN frequency = 'POPLATEK TYDNE'     THEN 'Weekly'
        WHEN frequency = 'POPLATEK PO OBRATU' THEN 'After transaction'
        ELSE frequency
    END
WHERE account_id > 0;

-- 7c: Verify (no Czech values should remain; total must stay 1,056,320)
SELECT type,
       operation,
       COUNT(*) AS trans_count,
       (SELECT COUNT(*) FROM trans) AS total_rows
FROM trans
GROUP BY type, operation
ORDER BY trans_count DESC;

SELECT frequency,
	   COUNT(*) AS cnt,
       (select count(*) from account)
FROM account GROUP BY frequency;

-- Result: type has only CREDIT/DEBIT, 6 English operations, total = 1,056,320.



-- =====================================================
-- Step 8: Make loan.status readable
-- Why: A/B/C/D codes are meaningless in a dashboard.
-- Source: dataset documentation (Berka, PKDD'99).
-- is_bad_loan: B and D = 1 (loan not paid / client in debt); used for default rate.
-- =====================================================

-- 8a: Add the new columns
ALTER TABLE loan
    ADD COLUMN status_desc  VARCHAR(40),
    ADD COLUMN is_bad_loan  TINYINT;
    
-- 8b: Fill the new columns
UPDATE loan
SET status_desc = CASE
        WHEN status = 'A' THEN 'Finished, paid'
        WHEN status = 'B' THEN 'Finished, not paid'
        WHEN status = 'C' THEN 'Running, OK'
        WHEN status = 'D' THEN 'Running, in debt'
    END,
    is_bad_loan = IF(status IN ('B', 'D'), 1, 0)
WHERE loan_id > 0;


-- 8c: Verify (expect 4 rows, no NULL status_desc, total 682)
SELECT status, status_desc, is_bad_loan,
       COUNT(*)              AS loans,
       SUM(COUNT(*)) OVER () AS total_loans
FROM loan
GROUP BY status, status_desc, is_bad_loan
ORDER BY status;



-- =====================================================
-- Step 9: Clean district table
-- Why: the source documentation mentions missing values for 1995. Check whether they exist
--      in this copy, and fix column types so values are exact and compact.
-- =====================================================

-- 9a: Pre-check. Which districts have missing values?
SELECT district_id, district_name, unemployment_rate_95, crimes_95
FROM district
WHERE unemployment_rate_95 IS NULL OR crimes_95 IS NULL;


-- 9b: Pre-check. Text lengths and region values before changing to VARCHAR
SELECT MAX(LENGTH(district_name)) AS max_name_len,
       MAX(LENGTH(region))        AS max_region_len,
       COUNT(DISTINCT region)     AS regions,
       COUNT(*)                   AS districts
FROM district;


-- 9c: Change data types
--     DECIMAL for rates (exact), VARCHAR for names (text is unnecessarily large).
ALTER TABLE district
    MODIFY district_name         VARCHAR(50),
    MODIFY region                VARCHAR(50),
    MODIFY urban_ratio           DECIMAL(5,1),
    MODIFY unemployment_rate_95  DECIMAL(5,2),
    MODIFY unemployment_rate_96  DECIMAL(5,2);
    
    
-- 9d: Verify
DESCRIBE district;
SELECT COUNT(*) AS districts FROM district;

-- Result: 0 rows, no NULLs found in unemployment_rate_95 or crimes_95.

-- 9e: Fix the missing row. The import wizard silently dropped district 69 (Jesenik)
--     because the source file has '?' in two numeric columns (unemployment_rate_95, crimes_95).
--     Re-inserted manually; the two unknown values are stored as NULL (not imputed).
INSERT INTO district
    (district_id, district_name, region, inhabitants,
     municipalities_lt_499, municipalities_500_1999, municipalities_2000_9999, municipalities_gt_10000,
     cities, urban_ratio, avg_salary, unemployment_rate_95, unemployment_rate_96,
     entrepreneurs_per_1000, crimes_95, crimes_96)
VALUES
    (69, 'Jesenik', 'north Moravia', 42821,
     4, 13, 5, 1,
     3, 48.4, 8173, NULL, 7.01,
     124, NULL, 1358);

-- Verify (expect 77 rows; unemployment_rate_95 and crimes_95 NULL for district 69)
SELECT COUNT(*) AS districts FROM district;
SELECT * FROM district WHERE district_id = 69;


-- =====================================================
-- Step 10: Final validation
-- Why: confirm cleaning did not lose rows and that tables still link correctly.
-- =====================================================

-- 10a: Row counts (cleaning must not change them)
SELECT 'district' AS table_name, COUNT(*) AS row_count FROM district
UNION ALL SELECT 'account', COUNT(*) FROM account
UNION ALL SELECT 'client',  COUNT(*) FROM client
UNION ALL SELECT 'disp',    COUNT(*) FROM disp
UNION ALL SELECT 'card',    COUNT(*) FROM card
UNION ALL SELECT 'loan',    COUNT(*) FROM loan
UNION ALL SELECT 'order',   COUNT(*) FROM `order`
UNION ALL SELECT 'trans',   COUNT(*) FROM trans;
-- Result: district 77, account 4,500, client 5,369, disp 5,369,
--         card 892, loan 682, order 6,471, trans 1,056,320.

-- 10b: Referential integrity (orphan rows). Every result should be 0.
SELECT 'loan without account' AS check_name, COUNT(*) AS orphans
FROM loan l LEFT JOIN account a ON a.account_id = l.account_id
WHERE a.account_id IS NULL
UNION ALL
SELECT 'account without district', COUNT(*)
FROM account a LEFT JOIN district d ON d.district_id = a.district_id
WHERE d.district_id IS NULL
UNION ALL
SELECT 'client without district', COUNT(*)
FROM client c LEFT JOIN district d ON d.district_id = c.district_id
WHERE d.district_id IS NULL
UNION ALL
SELECT 'disp without client', COUNT(*)
FROM disp p LEFT JOIN client c ON c.client_id = p.client_id
WHERE c.client_id IS NULL
UNION ALL
SELECT 'disp without account', COUNT(*)
FROM disp p LEFT JOIN account a ON a.account_id = p.account_id
WHERE a.account_id IS NULL
UNION ALL
SELECT 'trans without account', COUNT(*)
FROM trans t LEFT JOIN account a ON a.account_id = t.account_id
WHERE a.account_id IS NULL;
-- Result: 0 orphans in every check.

-- 10c: Final structure of every table
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'berka_bank'
ORDER BY table_name, ordinal_position;
