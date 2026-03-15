/* ===========================================================
SQL Script: eda_queries.sql
Purpose: Perform exploratory data analysis to understand the
structure, distributions, and behavioural patterns within the
dog registration dataset prior to visualisation in Power BI.
Prepared By: Gabriel Wu
Project: Analysis of Dog Registration Compliance & Incentives in Hamilton, New Zealand
=========================================================== */

-- Inspect key attributes used for analysis in DimDog (dog demographics and location)
SELECT Dog_Number, Kept_At_Suburb, Kept_At_Post_Code, Kept_At_Town, Active_Dog_Record 
FROM dbo.DimDog;

-- Inspect registration attributes including fee structure and payment information
SELECT Dog_Number, Registration_Key, Registration_From, Registration_To, 
Effective_Date, Calculated_Fee, Fee_Code, Fee_Code_Description, Amount_Paid 
FROM dbo.FactRegistration;

-- Inspect transaction attributes related to payment behaviour
SELECT Registration_Key, Transaction_Date, Transaction_Value, Transaction_Type 
FROM dbo.FactTransaction;

/* -----------------------------------------------------
   EDA Sections
1. Dog Population Overview
2. Late Payment Behaviour (FactTransaction)
3. Discount Uptake Patterns (FactTransaction)
4. Registration Lifecycle Analysis (FactRegistration)
5. Geographic Patterns (Suburb-Level)
6. Time-Series Behaviour
-------------------------------------------------------- */

/* -----------------------------------------------------
1. Dog Population Overview
   Objective: Understand total dogs, geographic coverage, and data quality
-------------------------------------------------------- */

-- 1.1 Total number of dogs in the dataset
SELECT COUNT(*) AS Total_Dogs
FROM dbo.DimDog;

-- 1.2 Identify missing geographic data for quality assessment
SELECT 
    SUM(CASE WHEN Kept_At_Suburb IS NULL THEN 1 ELSE 0 END) AS Null_Suburb,
    SUM(CASE WHEN Kept_At_Post_Code IS NULL THEN 1 ELSE 0 END) AS Null_PostCode,
    SUM(CASE WHEN Kept_At_Town IS NULL THEN 1 ELSE 0 END) AS Null_Town,
    COUNT(*) AS Total_Rows
FROM dbo.DimDog;

-- 1.3 Count of dogs by suburb (for geographic distribution and mapping)
SELECT Kept_At_Suburb,COUNT(*) AS Dog_Count
FROM dbo.DimDog
WHERE Kept_At_Suburb IS NOT NULL
GROUP BY Kept_At_Suburb
ORDER BY Dog_Count DESC;

-- 1.4 Identify suburbs with very few dogs (potential outliers for analysis)
SELECT Kept_At_Suburb, COUNT(*) AS Dog_Count
FROM dbo.DimDog
WHERE Kept_At_Suburb IS NOT NULL
GROUP BY Kept_At_Suburb
HAVING COUNT(*) < 5
ORDER BY Dog_Count ASC;

-- 1.5 Summary statistics for dog counts per suburb (avg, min, max, median)
WITH SuburbCounts AS (
    SELECT Kept_At_Suburb, COUNT(*) AS Dog_Count
    FROM dbo.DimDog
    WHERE Kept_At_Suburb IS NOT NULL
    GROUP BY Kept_At_Suburb
), 
MedianCalc AS (
    SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Dog_Count)
            OVER () AS Median_Dogs
    FROM SuburbCounts
)
SELECT 
    (SELECT AVG(Dog_Count) FROM SuburbCounts) AS Avg_Dogs_Per_Suburb,
    (SELECT MIN(Dog_Count) FROM SuburbCounts) AS Min_Dogs,
    (SELECT MAX(Dog_Count) FROM SuburbCounts) AS Max_Dogs,
    (SELECT TOP 1 Median_Dogs FROM MedianCalc) AS Median_Dogs;

/* -----------------------------------------------------
2. Late Payment Behaviour (FactTransaction)
   Purpose: Quantify late payments, identify trends over time,
   registration categories, and geographic hotspots.
   Relevant for: KPI dashboards and targeted interventions.
-------------------------------------------------------- */

-- 2.1 Total number of late payment transactions
-- (High-level KPI for overall compliance)
SELECT COUNT(*) AS LatePayment_Count
FROM dbo.FactTransaction
WHERE Transaction_Type = 'Late Payment Penalty Fee';

-- 2.2 Late payments over time (year/month)
SELECT 
    YEAR(Transaction_Date) AS Year,
    MONTH(Transaction_Date) AS Month,
    COUNT(*) AS LatePayment_Count
FROM dbo.FactTransaction
WHERE Transaction_Type = 'Late Payment Penalty Fee'
GROUP BY YEAR(Transaction_Date), MONTH(Transaction_Date)
ORDER BY Year, Month;

-- 2.3 Flag historic outlier dates (before 2000) for exclusion
-- Ensures KPIs reflect relevant current data
SELECT Transaction_Date, COUNT(*) AS Count_Records
FROM dbo.FactTransaction
WHERE YEAR(Transaction_Date) < 2000 -- revisit this
GROUP BY Transaction_Date
ORDER BY Count_Records DESC;

-- 2.4 Late payments by registration category
-- Useful for identifying categories with higher risk of late payments
SELECT fr.Fee_Code_Description, COUNT(*) AS LatePayment_Count
FROM dbo.FactTransaction ft
JOIN dbo.FactRegistration fr 
    ON ft.Registration_Key = fr.Registration_Key
WHERE ft.Transaction_Type = 'Late Payment Penalty Fee'
GROUP BY fr.Fee_Code_Description
ORDER BY LatePayment_Count DESC;

-- 2.5 Late payments by suburb
-- Reveals geographic patterns and hotspots for targeted interventions
SELECT dd.Kept_At_Suburb, COUNT(*) AS LatePayment_Count
FROM dbo.FactTransaction ft
JOIN dbo.FactRegistration fr 
    ON ft.Registration_Key = fr.Registration_Key
JOIN dbo.DimDog dd 
    ON fr.Dog_Number = dd.Dog_Number
WHERE ft.Transaction_Type = 'Late Payment Penalty Fee'
  AND dd.Kept_At_Suburb IS NOT NULL
GROUP BY dd.Kept_At_Suburb
ORDER BY LatePayment_Count DESC;

-- 2.6 Late payment rate by suburb (% of registrations incurring late fees)
-- Key KPI for compliance dashboards and targeted follow-ups
WITH LatePayments AS (
    SELECT fr.Registration_Key, dd.Kept_At_Suburb, 1 AS IsLate
    FROM dbo.FactTransaction ft
    JOIN dbo.FactRegistration fr 
        ON ft.Registration_Key = fr.Registration_Key
    JOIN dbo.DimDog dd
        ON fr.Dog_Number = dd.Dog_Number
    WHERE ft.Transaction_Type = 'Late Payment Penalty Fee'
),
Registrations AS (
    SELECT fr.Registration_Key, dd.Kept_At_Suburb
    FROM dbo.FactRegistration fr
    JOIN dbo.DimDog dd 
        ON fr.Dog_Number = dd.Dog_Number
    WHERE dd.Kept_At_Suburb IS NOT NULL
)
SELECT 
    r.Kept_At_Suburb,
    COUNT(lp.IsLate) AS LatePayment_Count,
    COUNT(*) AS Total_Registrations,
    CAST(COUNT(lp.IsLate) AS FLOAT) / COUNT(*) AS LatePayment_Rate
FROM Registrations r
LEFT JOIN LatePayments lp 
    ON r.Registration_Key = lp.Registration_Key
GROUP BY r.Kept_At_Suburb
ORDER BY LatePayment_Rate DESC;

/* -----------------------------------------------------
3. Discount Uptake Patterns (FactTransaction)
   Analyse the usage of registration discounts (Fenced Property, Neutering, Obedience Training, Permanent Identification) 
   to understand popularity, compliance incentives, timing, and geographic patterns.
   This informs stakeholders about which incentive programmes are effective and where uptake could improve.
-------------------------------------------------------- */

-- 3.1 List all discount transaction types
-- Identify the specific transaction types that qualify as discounts
SELECT DISTINCT Transaction_Type
FROM dbo.FactTransaction
WHERE Transaction_Type LIKE '%Fenced%'
   OR Transaction_Type LIKE '%Neuter%'
   OR Transaction_Type LIKE '%Obedience%'
   OR Transaction_Type LIKE '%Permanent%';

-- 3.2 Diagnostic: Check discount transactions with missing registration keys
-- Assess data quality and ensure discount transactions are linked to registrations
SELECT 
    SUM(CASE WHEN Registration_Key IS NULL THEN 1 END) AS NullRegID,
    SUM(CASE WHEN Registration_Key IS NOT NULL THEN 1 END) AS HasRegID
FROM dbo.FactTransaction
WHERE Transaction_Type LIKE '%Fenced%'
   OR Transaction_Type LIKE '%Neuter%'
   OR Transaction_Type LIKE '%Obedience%'
   OR Transaction_Type LIKE '%Permanent%';

-- 3.3 Flag discount transactions
-- Create a binary indicator (IsDiscount) for easier aggregation and analysis
SELECT Registration_Key, Transaction_Date, Transaction_Type,
    CASE 
        WHEN Transaction_Type LIKE '%Fenced%' 
          OR Transaction_Type LIKE '%Neuter%'
          OR Transaction_Type LIKE '%Obedience%'
          OR Transaction_Type LIKE '%Permanent%'
        THEN 1 ELSE 0 
    END AS IsDiscount
FROM dbo.FactTransaction
ORDER BY IsDiscount DESC;

-- 3.4 Count discount transactions by type
-- Identify which discounts are most commonly applied
SELECT Transaction_Type, COUNT(*) AS Discount_Count
FROM dbo.FactTransaction
WHERE Transaction_Type LIKE '%Fenced%' 
   OR Transaction_Type LIKE '%Neuter%'
   OR Transaction_Type LIKE '%Obedience%'
   OR Transaction_Type LIKE '%Permanent%'
GROUP BY Transaction_Type
ORDER BY Discount_Count DESC;

-- 3.5 Detect duplicate discount entries
-- Ensure data integrity by identifying repeated discount transactions for the same registration on the same date
SELECT Registration_Key, Transaction_Type, Transaction_Date, COUNT(*) AS Duplicate_Count
FROM dbo.FactTransaction
WHERE Transaction_Type LIKE '%Fenced%' 
   OR Transaction_Type LIKE '%Neuter%'
   OR Transaction_Type LIKE '%Obedience%'
   OR Transaction_Type LIKE '%Permanent%'
GROUP BY Registration_Key, Transaction_Type, Transaction_Date
HAVING COUNT(*) > 1
ORDER BY Duplicate_Count DESC;

-- 3.6 Identify discounts applied after late payment penalties
-- Examine timing of discounts relative to late fees to understand incentive effectiveness
WITH Late AS (
    SELECT Registration_Key, MIN(Transaction_Date) AS LateDate
    FROM dbo.FactTransaction
    WHERE Transaction_Type = 'Late Payment Penalty Fee'
    GROUP BY Registration_Key
),
Discounts AS (
    SELECT Registration_Key, Transaction_Date AS DiscountDate
    FROM dbo.FactTransaction
    WHERE Transaction_Type LIKE '%Fenced%' 
       OR Transaction_Type LIKE '%Neuter%'
       OR Transaction_Type LIKE '%Obedience%'
       OR Transaction_Type LIKE '%Permanent%'
)
SELECT d.Registration_Key, d.DiscountDate, l.LateDate
FROM Discounts d
JOIN Late l 
    ON d.Registration_Key = l.Registration_Key
WHERE d.DiscountDate > l.LateDate
ORDER BY d.DiscountDate;

-- 3.7 Detect value outliers in discount transactions
-- Identify unusually high or low transaction values which may indicate errors or special cases
SELECT Transaction_Type, Transaction_Value
FROM dbo.FactTransaction
WHERE (Transaction_Type LIKE '%Fenced%' 
    OR Transaction_Type LIKE '%Neuter%'
    OR Transaction_Type LIKE '%Obedience%'
    OR Transaction_Type LIKE '%Permanent%')
  AND (Transaction_Value < -100 OR Transaction_Value > 100)
ORDER BY Transaction_Value;

-- 3.8 Discounts without matching registrations
-- Identify transactions that cannot be linked to a registration, highlighting potential data issues
SELECT ft.Transaction_Type, COUNT(*) AS Count_NoRegistration
FROM dbo.FactTransaction ft
LEFT JOIN dbo.FactRegistration fr 
    ON ft.Registration_Key = fr.Registration_Key
WHERE (ft.Transaction_Type LIKE '%Fenced%' 
    OR ft.Transaction_Type LIKE '%Neuter%'
    OR ft.Transaction_Type LIKE '%Obedience%'
    OR ft.Transaction_Type LIKE '%Permanent%')
  AND fr.Registration_Key IS NULL
GROUP BY ft.Transaction_Type;

-- 3.9 Discount uptake by suburb
-- Measure discount participation across geographic areas to support stakeholder insights
WITH Discounts AS (
    SELECT fr.Registration_Key, dd.Kept_At_Suburb, 1 AS IsDiscount
    FROM dbo.FactTransaction ft
    JOIN dbo.FactRegistration fr 
        ON ft.Registration_Key = fr.Registration_Key
    JOIN dbo.DimDog dd 
        ON fr.Dog_Number = dd.Dog_Number
    WHERE ft.Transaction_Type LIKE '%Fenced%' 
       OR ft.Transaction_Type LIKE '%Neuter%'
       OR ft.Transaction_Type LIKE '%Obedience%'
       OR ft.Transaction_Type LIKE '%Permanent%'
),
Registrations AS (
    SELECT fr.Registration_Key, dd.Kept_At_Suburb
    FROM dbo.FactRegistration fr
    JOIN dbo.DimDog dd 
        ON fr.Dog_Number = dd.Dog_Number
    WHERE dd.Kept_At_Suburb IS NOT NULL
)
SELECT 
    r.Kept_At_Suburb,
    COUNT(d.IsDiscount) AS Discount_Count,
    COUNT(*) AS Total_Registrations,
    CAST(COUNT(d.IsDiscount) AS FLOAT) / COUNT(*) AS Discount_Rate
FROM Registrations r
LEFT JOIN Discounts d 
    ON r.Registration_Key = d.Registration_Key
GROUP BY r.Kept_At_Suburb
ORDER BY Discount_Rate DESC;

/* -----------------------------------------------------
4. Registration Lifecycle Analysis (FactRegistration)
   Assess data quality and payment behaviour for accurate KPIs.
   Focuses on missing payment information and registrations without transactions,
   ensuring late-payment and discount analyses are based on valid data.
-------------------------------------------------------- */

-- 4.1 Check for Missing Payment or Effective Date
-- Identify registrations with incomplete payment data, which may affect KPIs.
SELECT 
    SUM(CASE WHEN Amount_Paid IS NULL THEN 1 ELSE 0 END) AS Null_AmountPaid,
    SUM(CASE WHEN Effective_Date IS NULL THEN 1 ELSE 0 END) AS Null_EffectiveDate,
    COUNT(*) AS Total_Registrations
FROM dbo.FactRegistration;


-- 4.2 Identify Registrations Without Any Transactions
-- Registrations without transactions may represent waived fees,
-- abandoned registrations, or system placeholders. These cannot have discounts or late payments.
SELECT fr.Registration_Key, fr.Dog_Number, fr.Registration_From, fr.Registration_To
FROM dbo.FactRegistration fr
LEFT JOIN dbo.FactTransaction ft 
    ON fr.Registration_Key = ft.Registration_Key
WHERE ft.Registration_Key IS NULL;

/* -----------------------------------------------------
5. Geographic Patterns (Suburb-Level)
   Focus on dog population, late-payment behaviour, and discount uptake
   to identify geographic trends and support decision-making.
-------------------------------------------------------- */

-- 5.1 Dog Population by Suburb
-- Insight: Establish the baseline population in each suburb. 
-- Needed to calculate rates of late payments and discount uptake.
SELECT Kept_At_Suburb, COUNT(*) AS Dog_Count
FROM dbo.DimDog
WHERE Kept_At_Suburb IS NOT NULL
GROUP BY Kept_At_Suburb
ORDER BY Dog_Count DESC;

-- 5.2 Late Payment Rate by Suburb
-- Insight: Identify suburbs with high late payment activity. 
-- LatePayment_Rate = % of registrations that incurred late penalties.
WITH Late AS (
    SELECT fr.Registration_Key, dd.Kept_At_Suburb, 1 AS IsLate
    FROM dbo.FactTransaction ft
    JOIN dbo.FactRegistration fr 
        ON ft.Registration_Key = fr.Registration_Key
    JOIN dbo.DimDog dd 
        ON fr.Dog_Number = dd.Dog_Number
    WHERE ft.Transaction_Type = 'Late Payment Penalty Fee'
),
Regs AS (
    SELECT fr.Registration_Key, dd.Kept_At_Suburb
    FROM dbo.FactRegistration fr
    JOIN dbo.DimDog dd
        ON fr.Dog_Number = dd.Dog_Number
    WHERE dd.Kept_At_Suburb IS NOT NULL
)
SELECT 
    r.Kept_At_Suburb,
    COUNT(l.IsLate) AS LatePayment_Count,
    COUNT(*) AS Total_Registrations,
    CAST(COUNT(l.IsLate) AS FLOAT) / COUNT(*) AS LatePayment_Rate
FROM Regs r
LEFT JOIN Late l 
    ON r.Registration_Key = l.Registration_Key
GROUP BY r.Kept_At_Suburb
ORDER BY LatePayment_Rate DESC;

-- 5.3 Discount Uptake by Suburb
-- Insight: Identify where financial incentives are being applied.
-- Discount_Rate = % of registrations receiving a discount.
WITH Discounts AS (
    SELECT fr.Registration_Key, dd.Kept_At_Suburb, 1 AS IsDiscount
    FROM dbo.FactTransaction ft
    JOIN dbo.FactRegistration fr 
        ON ft.Registration_Key = fr.Registration_Key
    JOIN dbo.DimDog dd 
        ON fr.Dog_Number = dd.Dog_Number
    WHERE ft.Transaction_Type LIKE '%Fenced%'
       OR ft.Transaction_Type LIKE '%Neuter%'
       OR ft.Transaction_Type LIKE '%Obedience%'
       OR ft.Transaction_Type LIKE '%Permanent%'
),
Regs AS (
    SELECT fr.Registration_Key, dd.Kept_At_Suburb
    FROM dbo.FactRegistration fr
    JOIN dbo.DimDog dd 
        ON fr.Dog_Number = dd.Dog_Number
    WHERE dd.Kept_At_Suburb IS NOT NULL
)
SELECT 
    r.Kept_At_Suburb,
    COUNT(d.IsDiscount) AS Discount_Count,
    COUNT(*) AS Total_Registrations,
    CAST(COUNT(d.IsDiscount) AS FLOAT) / COUNT(*) AS Discount_Rate
FROM Regs r
LEFT JOIN Discounts d 
    ON r.Registration_Key = d.Registration_Key
GROUP BY r.Kept_At_Suburb
ORDER BY Discount_Rate DESC;


-- 5.4 Combined Suburb Metrics: Population, Late Payments, Discounts
-- Insight: Correlate dog population, late payment activity, and discount uptake.
WITH Base AS (
    SELECT fr.Registration_Key, dd.Kept_At_Suburb
    FROM dbo.FactRegistration fr
    JOIN dbo.DimDog dd 
        ON fr.Dog_Number = dd.Dog_Number
    WHERE dd.Kept_At_Suburb IS NOT NULL
),
Late AS (
    SELECT DISTINCT fr.Registration_Key, dd.Kept_At_Suburb, 1 AS IsLate
    FROM dbo.FactTransaction ft
    JOIN dbo.FactRegistration fr 
        ON ft.Registration_Key = fr.Registration_Key
    JOIN dbo.DimDog dd 
        ON fr.Dog_Number = dd.Dog_Number
    WHERE ft.Transaction_Type = 'Late Payment Penalty Fee'
),
Discounts AS (
    SELECT DISTINCT fr.Registration_Key, dd.Kept_At_Suburb, 1 AS IsDiscount
    FROM dbo.FactTransaction ft
    JOIN dbo.FactRegistration fr 
        ON ft.Registration_Key = fr.Registration_Key
    JOIN dbo.DimDog dd 
        ON fr.Dog_Number = dd.Dog_Number
    WHERE ft.Transaction_Type LIKE '%Fence%'
       OR ft.Transaction_Type LIKE '%Neut%'
       OR ft.Transaction_Type LIKE '%Obed%'
       OR ft.Transaction_Type LIKE '%Perm%'
)
SELECT 
    b.Kept_At_Suburb,
    -- Dog population baseline
    COUNT(DISTINCT b.Registration_Key) AS Total_Registrations,
    -- Late payments
    COUNT(DISTINCT l.Registration_Key) AS LatePayment_Count,
    CAST(COUNT(DISTINCT l.Registration_Key) AS FLOAT) 
        / COUNT(DISTINCT b.Registration_Key) AS LatePayment_Rate,
    -- Discounts
    COUNT(DISTINCT d.Registration_Key) AS Discount_Count,
    CAST(COUNT(DISTINCT d.Registration_Key) AS FLOAT) 
        / COUNT(DISTINCT b.Registration_Key) AS Discount_Rate
FROM Base b
LEFT JOIN Late l 
    ON b.Registration_Key = l.Registration_Key
LEFT JOIN Discounts d 
    ON b.Registration_Key = d.Registration_Key
GROUP BY b.Kept_At_Suburb
ORDER BY LatePayment_Rate DESC;

/* -----------------------------------------------------
6. Time-Series Behaviour
   Understand seasonal and annual trends in registrations, payments, and discount uptake.
   Supports the Communication Team and KPI monitoring.
------------------------------------------------------- */

-- 6.1 Total Transaction Volume Over Time
-- Insight: Shows overall activity in the system, useful for spotting peaks in registrations and payments.
SELECT YEAR(Transaction_Date) AS Year, MONTH(Transaction_Date) AS Month, COUNT(*) AS Transaction_Count
FROM dbo.FactTransaction
WHERE YEAR(Transaction_Date) >= 2020 
GROUP BY YEAR(Transaction_Date), MONTH(Transaction_Date)
ORDER BY Year, Month;

-- 6.2 Late Payments Over Time
-- Insight: Tracks late payment patterns. Peaks often follow payment deadlines; can reflect policy or communication effects.
SELECT YEAR(Transaction_Date) AS Year, MONTH(Transaction_Date) AS Month, COUNT(*) AS LatePayment_Count
FROM dbo.FactTransaction
WHERE Transaction_Type = 'Late Payment Penalty Fee'
  AND YEAR(Transaction_Date) >= 2020
GROUP BY YEAR(Transaction_Date), MONTH(Transaction_Date)
ORDER BY Year, Month;

-- 6.3 Prompt Payments Over Time
-- Insight: Shows timely payments. Comparing prompt vs late payments can reveal gaps in communication or engagement.
SELECT YEAR(Transaction_Date) AS Year, MONTH(Transaction_Date) AS Month, COUNT(*) AS PromptPayment_Count
FROM dbo.FactTransaction
WHERE Transaction_Type = 'Prompt Payment'
  AND YEAR(Transaction_Date) >= 2020
GROUP BY YEAR(Transaction_Date), MONTH(Transaction_Date)
ORDER BY Year, Month;

-- 6.4 Diagnostic: Check Discount Uptake Over Time
-- Insight: Highlights whether incentive usage is stable or seasonal. 
SELECT YEAR(Transaction_Date) AS Year, MONTH(Transaction_Date) AS Month, COUNT(*) AS Discount_Count
FROM dbo.FactTransaction
WHERE (Transaction_Type LIKE '%Fenced%'
   OR Transaction_Type LIKE '%Neuter%'
   OR Transaction_Type LIKE '%Obedience%'
   OR Transaction_Type LIKE '%Permanent%'
   )
  AND YEAR(Transaction_Date) >= 2020
GROUP BY YEAR(Transaction_Date), MONTH(Transaction_Date)
ORDER BY Year, Month;

-- 6.5 Check Range of Discount Transactions
-- Identify the earliest and latest dates for discount-related transactions
SELECT 
    MIN(Transaction_Date) AS FirstDiscount,
    MAX(Transaction_Date) AS LastDiscount
FROM dbo.FactTransaction
WHERE Transaction_Type LIKE '%Fenc%'
   OR Transaction_Type LIKE '%Neut%'
   OR Transaction_Type LIKE '%Obed%'
   OR Transaction_Type LIKE '%Perm%';

-- 6.6 Registration Creation Over Time
-- Insight: Tracks growth in dog registrations and system capture consistency.
SELECT YEAR(Registration_From) AS Year, COUNT(*) AS Registration_Count
FROM dbo.FactRegistration
WHERE YEAR(Registration_From) >= 2020
GROUP BY YEAR(Registration_From)
ORDER BY Year;

-- 6.7 Data Quality Over Time
-- Insight: Tracks missing key data (Amount_Paid, Effective_Date). 
-- Increases in nulls indicate declining data capture quality.
SELECT 
    YEAR(Registration_From) AS Year,
    SUM(CASE WHEN Amount_Paid IS NULL THEN 1 ELSE 0 END) AS Null_AmountPaid,
    SUM(CASE WHEN Effective_Date IS NULL THEN 1 ELSE 0 END) AS Null_EffectiveDate,
    COUNT(*) AS Total_Registrations
FROM dbo.FactRegistration
WHERE YEAR(Registration_From) >= 2020
GROUP BY YEAR(Registration_From)
ORDER BY Year;

-- 6.8 Combined Time-Series Dataset
-- Insight: Unified dataset for Power BI visuals (line charts, area charts, KPI cards).
-- Combines late payments, prompt payments, and discount uptake per month.
SELECT 
    YEAR(ft.Transaction_Date) AS Year,
    MONTH(ft.Transaction_Date) AS Month,
    SUM(CASE WHEN ft.Transaction_Type = 'Late Payment Penalty Fee' THEN 1 ELSE 0 END) AS LatePayments,
    SUM(CASE WHEN ft.Transaction_Type = 'Prompt Payment' THEN 1 ELSE 0 END) AS PromptPayments,
    SUM(CASE WHEN ft.Transaction_Type LIKE '%Fenced%'
           OR ft.Transaction_Type LIKE '%Neuter%'
           OR ft.Transaction_Type LIKE '%Obedience%'
           OR ft.Transaction_Type LIKE '%Permanent%' THEN 1 ELSE 0 END) AS Discounts,
    COUNT(*) AS TotalTransactions
FROM dbo.FactTransaction ft
WHERE YEAR(ft.Transaction_Date) >= 2020
GROUP BY YEAR(ft.Transaction_Date), MONTH(ft.Transaction_Date)
ORDER BY Year, Month;