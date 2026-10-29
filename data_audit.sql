-- Data Audit
-- Query 1: Check row counts, data range and data quality of all tables 

USE berka_bank;

SELECT 'district' AS table_name, COUNT(*) AS row_count FROM district
UNION ALL SELECT 'account', COUNT(*) FROM account
UNION ALL SELECT 'client',  COUNT(*) FROM client
UNION ALL SELECT 'disp',    COUNT(*) FROM disp
UNION ALL SELECT 'card',    COUNT(*) FROM card
UNION ALL SELECT 'loan',    COUNT(*) FROM loan
UNION ALL SELECT 'order',   COUNT(*) FROM `order`
UNION ALL SELECT 'trans',   COUNT(*) FROM trans;

-- Query 2: Data quality check for trans table
select 
	min(trans_date) as first_trans_date,
    max(trans_date) as last_trans_date,
    sum(amount is null) as null_amount,
    sum(balance is null) as null_balance,
    count(distinct account_id) unique_accounts
from trans;


-- Query 3a: Transaction categories
select 
	type,
    operation,
    count(*) as trans_count
from trans
group by type, operation
order by trans_count desc;


-- Query 3b: What are the transactions with empty operation?
SELECT k_symbol, COUNT(*) AS trans_count
FROM trans
WHERE operation = ''
GROUP BY k_symbol
ORDER BY trans_count DESC;


-- Query 4: Structure of tables imported with the wizard
DESCRIBE account;
DESCRIBE loan;
DESCRIBE client;

-- Finding: date columns in loan/account are INT (YYMMDD), money columns are DOUBLE,
--          no primary keys. birth_number in client encodes birth date and gender.
-- Decision: fix types and decode birth_number in the cleaning step.
    