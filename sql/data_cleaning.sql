/* ===========================================================
SQL Script: data_cleaning.sql
Purpose: Prepare, clean, and standardise dog registration data for analysis.
Prepared By: Gabriel Wu
Project: Analysis of Dog Registration Compliance & Incentives in Hamilton, New Zealand
=========================================================== */

/* -----------------------------------------------------
  Table of Content
1. Data Preparation & PK constraints
2. Formatting / Standardise
3. Handling Missing Data
4. Duplicate Checks
5. Removing Duplicates
6. Structural Data Validation
7. Handling Outliers
----------------------------------------------------- */

/* -----------------------------------------------------
1. Data Preparation & Primary Key Constraints
   - Copy raw staging tables into clean working tables.
   - Apply initial filtering to include only relevant records.
   - These tables will be used for cleaning, standardisation,
     and building the Power BI data model.
----------------------------------------------------- */

-- 1.1 Create DimDog table for dog-level attributes (e.g., suburb, postcode)
SELECT *
INTO dbo.DimDog
FROM dbo.Dog_Stage;

-- 1.2 Create FactRegistration table for registration periods, fees, and links to DimDog and FactTransaction tables
SELECT *
INTO dbo.FactRegistration
FROM dbo.Dog_Registration_Stage;

-- 1.3 Create FactTransaction table for payment, penalty, and discount transactions. Filter for 'Animal Registration' accounts only
SELECT *
INTO dbo.FactTransaction
FROM dbo.Dog_Transaction_Stage
WHERE Type_Of_Account = 'Animal Registration';

-- 1.4 Add surrogate primary key constraints to ensure uniqueness
ALTER TABLE dbo.DimDog
ADD CONSTRAINT PK_DimDog PRIMARY KEY (FID);

ALTER TABLE dbo.FactRegistration
ADD CONSTRAINT PK_FactRegistration PRIMARY KEY (FID);

ALTER TABLE dbo.FactTransaction
ADD CONSTRAINT PK_FactTransaction PRIMARY KEY (FID);

/* -----------------------------------------------------
2. Formatting & Standardisation
   - Ensure column names and values are consistent and audit-ready.
   - Correct abbreviations and spelling for clarity.
----------------------------------------------------- */

-- 2.1 Correct suburb abbreviation in DimDog for consistency
UPDATE dbo.DimDog
SET Kept_At_Suburb = REPLACE(Kept_At_Suburb, 'RD ', 'Rural Hamilton ')
WHERE Kept_At_Suburb LIKE 'RD %';

-- 2.2 Standardise Fee_Code_Description values in FactRegistration
UPDATE dbo.FactRegistration
SET Fee_Code_Description = 'Probationary & Dangerous'
WHERE Fee_Code_Description = 'Probat. & Dangerous';

UPDATE dbo.FactRegistration
SET Fee_Code_Description = 'Disability Assist Dog'
WHERE Fee_Code_Description = 'DisabilityAssistDog';

-- 2.3 Rename columns to standardise keys for table joins
EXEC sp_rename 'dbo.FactRegistration.Registration_ID', 'Registration_Key', 'COLUMN';
EXEC sp_rename 'dbo.FactTransaction.Account_Number', 'Registration_Key', 'COLUMN';


/* -----------------------------------------------------
3. Missing Data Audit – Assess NULL counts and percentages
   across key analytical fields in each table.
----------------------------------------------------- */

-- 3.1 Calculate the number and percentage of NULL values for key demographic and location fields in DimDog
DECLARE @TableName SYSNAME = 'DimDog';
DECLARE @SchemaName SYSNAME = 'dbo';
DECLARE @SQL NVARCHAR(MAX) = N'';
SELECT @SQL = STRING_AGG(
    'SELECT ''' + COLUMN_NAME + ''' AS ColumnName, ' +
    'SUM(CASE WHEN [' + COLUMN_NAME + '] IS NULL THEN 1 ELSE 0 END) AS Nulls, ' +
    'CAST(SUM(CASE WHEN [' + COLUMN_NAME + '] IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(8,2)) AS NullPct ' +
    'FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName),
    CHAR(13) + 'UNION ALL' + CHAR(13)
)
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = @SchemaName
  AND TABLE_NAME = @TableName
  AND COLUMN_NAME IN (
      'Dog_Number','Kept_At_Suburb',
      'Kept_At_Post_Code','Kept_At_Town','Active_Dog_Record'
  );
EXEC sp_executesql @SQL;

-- 3.2 Calculate the number and percentage of NULL values for key registration and fee-related fields in FactRegistration
DECLARE @TableName SYSNAME = 'FactRegistration';
DECLARE @SchemaName SYSNAME = 'dbo';
DECLARE @SQL NVARCHAR(MAX) = N'';

SELECT @SQL = STRING_AGG(
    'SELECT ''' + COLUMN_NAME + ''' AS ColumnName, ' +
    'SUM(CASE WHEN [' + COLUMN_NAME + '] IS NULL THEN 1 ELSE 0 END) AS Nulls, ' +
    'CAST(SUM(CASE WHEN [' + COLUMN_NAME + '] IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(8,2)) AS NullPct ' +
    'FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName),
    CHAR(13) + 'UNION ALL' + CHAR(13)
)
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = @SchemaName
  AND TABLE_NAME = @TableName
  AND COLUMN_NAME IN (
      'Dog_Number', 'Registration_Key',
      'Registration_From', 'Registration_To',
      'Effective_Date', 'Calculated_Fee',
      'Fee_Code', 'Fee_Code_Description',
      'Amount_Paid'
  );
EXEC sp_executesql @SQL;

-- 3.3 Calculate the number and percentage of NULL values for key transaction fields in FactTransaction
DECLARE @TableName SYSNAME = 'FactTransaction';
DECLARE @SchemaName SYSNAME = 'dbo';
DECLARE @SQL NVARCHAR(MAX) = N'';

SELECT @SQL = STRING_AGG(
    'SELECT ''' + COLUMN_NAME + ''' AS ColumnName, ' +
    'SUM(CASE WHEN [' + COLUMN_NAME + '] IS NULL THEN 1 ELSE 0 END) AS Nulls, ' +
    'CAST(SUM(CASE WHEN [' + COLUMN_NAME + '] IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(8,2)) AS NullPct ' +
    'FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName),
    CHAR(13) + 'UNION ALL' + CHAR(13)
)
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = @SchemaName
  AND TABLE_NAME = @TableName
  AND COLUMN_NAME IN (
      'Registration_Key',
      'Transaction_Date',
      'Transaction_Value',
      'Transaction_Type'
  );
EXEC sp_executesql @SQL;

/* -------------------------
4. Duplicate Checks
   Verify the uniqueness and integrity of records across DimDog, FactRegistration, 
   and FactTransaction tables by checking for null FID values, duplicate keys, 
   and exact duplicate rows using key identifiers and hash comparisons.
----------------------------*/

-- 4.1 Check whether the FID column contains any NULL values in DimDog
SELECT COUNT(*) AS NullCount_DimDog
FROM dbo.DimDog
WHERE FID IS NULL;

-- 4.2 Identify duplicate FID values in DimDog to confirm row-level uniqueness
SELECT FID, COUNT(*) AS DuplicateCount_DimDog
FROM dbo.DimDog
GROUP BY FID
HAVING COUNT(*) > 1;

-- 4.3 Check whether the FID column contains any NULL values in FactRegistration
SELECT COUNT(*) AS NullCount_FactRegistration
FROM dbo.FactRegistration
WHERE FID IS NULL;

-- 4.4 Identify duplicate FID values in FactRegistration to ensure each record is uniquely identified
SELECT FID, COUNT(*) AS DuplicateCount_FactRegistration
FROM dbo.FactRegistration
GROUP BY FID
HAVING COUNT(*) > 1;

-- 4.5 Check whether the FID column contains any NULL values in FactTransaction
SELECT COUNT(*) AS NullCount_FactTransaction
FROM dbo.FactTransaction
WHERE FID IS NULL;

-- 4.6 Identify duplicate FID values in FactTransaction to verify transaction record uniqueness
SELECT FID, COUNT(*) AS DuplicateCount_FactTransaction
FROM dbo.FactTransaction
GROUP BY FID
HAVING COUNT(*) > 1;

-- 4.7 Detect exact duplicate records in DimDog using Dog_Number and row hash comparison
SELECT Dog_Number, hash_binary, COUNT(*) AS DuplicateCount
FROM dbo.DimDog
GROUP BY Dog_Number, hash_binary
HAVING COUNT(*) > 1;

-- 4.8 Inspect duplicate DimDog records using key descriptive attributes for easier validation
SELECT Dog_Number, Kept_At_Suburb, Date_Of_Birth, Animal_Sex, Primary_Breed, Primary_Colour, Active_Dog_Record, hash_binary, COUNT(*) AS DuplicateCount
FROM dbo.DimDog
GROUP BY Dog_Number, Kept_At_Suburb, Date_Of_Birth, Animal_Sex, Primary_Breed, Primary_Colour, Active_Dog_Record, hash_binary
HAVING COUNT(*) > 1;

-- 4.9 Detect duplicate registration records using Registration_Key and row hash comparison
SELECT Registration_Key, hash_binary, COUNT(*) AS DuplicateCount
FROM dbo.FactRegistration
GROUP BY Registration_Key, hash_binary
HAVING COUNT(*) > 1;

-- 4.10 Validate duplicate FactRegistration rows using key registration attributes
SELECT Registration_Key, Dog_Number, Registration_From, Registration_To, Calculated_Fee, hash_binary, COUNT(*) AS DuplicateCount
FROM dbo.FactRegistration
GROUP BY Registration_Key, Dog_Number, Registration_From, Registration_To, Calculated_Fee, hash_binary
HAVING COUNT(*) > 1;

-- 4.11 Detect duplicate transaction records using Registration_Key and row hash comparison
SELECT Registration_Key, hash_binary, COUNT(*) AS DuplicateCount
FROM dbo.FactTransaction
GROUP BY Registration_Key, hash_binary
HAVING COUNT(*) > 1;

-- 4.12 Identify exact duplicate transactions using key transaction attributes
SELECT Registration_Key, Transaction_Date, Transaction_Value, Transaction_Type, hash_binary, COUNT(*) AS DuplicateCount
FROM dbo.FactTransaction
GROUP BY Registration_Key, Transaction_Date, Transaction_Value, Transaction_Type, hash_binary
HAVING COUNT(*) > 1;

/* -----------------------------------------------------
5. Removing Duplicate Records
   Identify and remove exact duplicate rows using the
   ROW_NUMBER() window function, keeping the first
   occurrence of each record based on the FID.
----------------------------------------------------- */
-- 5.1 Remove duplicate records in DimDog based on Dog_Number and hash value
WITH Dedup AS ( 
SELECT *, ROW_NUMBER() OVER (
    PARTITION BY Dog_Number, hash_binary
    ORDER BY FID
) AS rn
    FROM dbo.DimDog
) DELETE FROM Dedup WHERE rn > 1;

-- 5.2 Remove duplicate records in FactRegistration based on Registration_Key and hash value
WITH Dedup AS (
SELECT *, ROW_NUMBER() OVER (
    PARTITION BY Registration_Key, hash_binary
    ORDER BY FID
) AS rn
    FROM dbo.FactRegistration
) DELETE FROM Dedup WHERE rn > 1;

-- 5.3 Remove duplicate records in FactTransaction based on Registration_Key and hash value
WITH Dedup AS (
SELECT *, ROW_NUMBER() OVER (
    PARTITION BY Registration_Key, hash_binary
    ORDER BY FID
) AS rn
    FROM dbo.FactTransaction
) DELETE FROM Dedup WHERE rn > 1;

/* -----------------------------------------------------
6. Structural Data Validation
   Verify data consistency, logical date order, and fee category alignment
----------------------------------------------------- */

-- 6.1 Verify registration dates are in logical order
SELECT Registration_Key, Registration_From, Registration_To
FROM dbo.FactRegistration
WHERE Registration_From > Registration_To;

-- 6.2 Identify records where Effective_Flag is 'N' but Effective_Date is populated
SELECT COUNT(*) AS CountWithDate
FROM dbo.FactRegistration
WHERE Effective_Flag = 'N' AND Effective_Date IS NOT NULL;

-- 6.3 Count records by DimDog and FactRegistration fee categories
SELECT dd.Fee_Description, fr.Fee_Code_Description, COUNT(*) AS RecordCount
FROM dbo.DimDog dd
JOIN dbo.FactRegistration fr
    ON dd.Dog_Number = fr.Dog_Number
GROUP BY dd.Fee_Description, fr.Fee_Code_Description
ORDER BY dd.Fee_Description, fr.Fee_Code_Description;

-- 6.4 Find mismatches between DimDog and FactRegistration fee categories
SELECT dd.Dog_Number,
       dd.Fee_Description AS DimDog_Fee,
       fr.Fee_Code_Description AS Fact_Fee
FROM dbo.DimDog dd
JOIN dbo.FactRegistration fr
    ON dd.Dog_Number = fr.Dog_Number
WHERE dd.Fee_Description <> fr.Fee_Code_Description;

/* -----------------------------------------------------
7. Handle Outliers
   Identify and manage anomalies in dates, payment values, and geographic locations
----------------------------------------------------- */

-- 7.1 Find FactRegistration records with dates outside expected range (pre-2000 or Registration_From > Registration_To)
SELECT * 
FROM FactRegistration
WHERE Registration_From < '2000-01-01'
   OR Registration_From > GETDATE()
   OR Registration_To < Registration_From;

-- 7.2 Find FactTransaction records with dates outside expected range (pre-2000 or future dates)
SELECT * 
FROM FactTransaction
WHERE Transaction_Date < '2000-01-01'
   OR Transaction_Date > GETDATE();

-- 7.3 Count number of records per year for FactRegistration to identify date distribution anomalies
SELECT 'Registration_From' AS DateField,
       YEAR(Registration_From) AS Yr,
       COUNT(*) AS Cnt
FROM FactRegistration
GROUP BY YEAR(Registration_From)
UNION ALL
SELECT 'Registration_To' AS DateField,
       YEAR(Registration_To) AS Yr,
       COUNT(*) AS Cnt
FROM FactRegistration
GROUP BY YEAR(Registration_To)
UNION ALL
SELECT 'Effective_Date' AS DateField,
       YEAR(Effective_Date) AS Yr,
       COUNT(*) AS Cnt
FROM FactRegistration
GROUP BY YEAR(Effective_Date)
ORDER BY DateField, Yr;

-- 7.4 Count number of records per year for FactTransaction to identify date distribution anomalies
SELECT YEAR(Transaction_Date) AS Yr, COUNT(*) AS Cnt
FROM FactTransaction
GROUP BY YEAR(Transaction_Date)
ORDER BY Yr;

-- 7.5 Identify negative or unusually high values in Amount_Paid (FactRegistration)
SELECT *
FROM FactRegistration
WHERE TRY_CAST(Amount_Paid AS DECIMAL(10,2)) < 0
   OR TRY_CAST(Amount_Paid AS DECIMAL(10,2)) > 500
ORDER BY TRY_CAST(Amount_Paid AS DECIMAL(10,2));

-- 7.6 Identify negative or unusually high Calculated_Fee (FactRegistration)
SELECT *
FROM FactRegistration
WHERE Calculated_Fee < 0
   OR Calculated_Fee > 500
ORDER BY Calculated_Fee;

-- 7.7 Identify negative or unusually high Transaction_Value (FactTransaction)
SELECT *
FROM FactTransaction
WHERE Transaction_Value < 0
   OR Transaction_Value > 500
ORDER BY Transaction_Value;

-- 7.8 Identify geographic anomalies: suburbs not in Hamilton or placeholders
SELECT DISTINCT Kept_At_Suburb, COUNT(*) AS CountSuburb
FROM dbo.DimDog
WHERE Kept_At_Suburb LIKE 'Rural Hamilton%'
    OR Kept_At_Suburb IS NULL
GROUP BY Kept_At_Suburb
ORDER BY CountSuburb;

-- 7.9 Identify suburbs with extremely high or low dog counts
SELECT Kept_At_Suburb, COUNT(*) AS DogCount
FROM DimDog
GROUP BY Kept_At_Suburb
HAVING COUNT(*) > 2000 OR COUNT(*) < 5;
