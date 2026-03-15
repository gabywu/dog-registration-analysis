# Dog Registration Compliance Analysis

**End-to-End Data Analytics Case Study**  
*Analysing registration behaviour, late payments, and incentive program adoption for Hamilton City Council dog registrations (2020–2024).*

---

## Project Overview

This project examines dog registration compliance and the effectiveness of council incentive programs using publicly available data from the [Waikato Open Data Co-Lab](https://data-waikatolass.opendata.arcgis.com/).  
It is a **self-directed portfolio project** conducted independently and is **not official work for Hamilton City Council**.

Key objectives:  
- Identify suburbs with higher rates of late dog registration  
- Explore participation in council discount programs  
- Examine potential relationships between late payments and incentives  
- Provide interactive dashboards for suburb-level and time-based insights  

---

## Data Sources

- **DimDog (Dimension Dog)** – Dog demographics and geographic information  
- **FactRegistration (Dog Registration)** – Registration and fee data  
- **FactTransaction (Dog Transaction)** – Payment behaviour and discount transactions  

All datasets are licensed under the Creative Commons Attribution 4.0 New Zealand License.

---

## Repository Contents

dog-registration-compliance-analysis/
│
├── Dog_Registration_Report.PDF # Full project report
├── data/
│ ├── data_cleaning_script.sql # SQL for cleaning & preparing data
│ └── eda_queries.sql # SQL queries for exploratory data analysis
├── dashboards/
│ └── dog_registration_compliance_incentive.pbix # Power BI dashboard
├── img/ # Power BI dashboard screenshots
└── README.md # Project overview and instructions

---

## Analytical Approach

- **Data Cleaning** – SQL scripts to filter transactions, remove duplicates, and standardise categories  
- **Exploratory Data Analysis (EDA)** – SQL and Power BI used to calculate late payment rates, discount uptake, and dog population distribution  
- **Power BI Dashboards** – Interactive visualisations for registration trends, late payments, and incentive participation  
- **Key Insights** – Seasonal peaks, geographic variation, and high-impact suburbs  
- **Recommendations** – Targeted reminders, outreach, promotion of incentives, and ongoing data quality monitoring  

---

## Key Findings

- Registrations peak sharply in July each year  
- Late payment rates vary significantly between suburbs  
- Discount programs show uneven adoption, with **no consistent correlation** to late payment behaviour  
- High-population suburbs have the greatest impact on overall compliance  

---

## Notes

- Missing values (~12–13% of payments/effective dates) may slightly affect calculations  
- Descriptive analysis only; no causal relationships are established  
- All dashboards and scripts are included for portfolio review  

---

## Reports & Files

**Power BI Dashboard:** Open `dog_registration_compliance_incentive.pbix` to interact with dashboards and explore suburb-level trends, registration patterns, and discount uptake.  
**Report:** Review `Dog_Registration_Report.PDF` for the full analysis, key findings, and recommendations.  
**SQL Scripts:**  

- `data_cleaning_script.sql` – Contains the full data cleaning and transformation workflow. This script handles missing values, duplicates, and standardises data to prepare the raw dataset for analysis.  
- `eda_queries.sql` – Performs exploratory analysis on the cleaned dataset, calculating key metrics such as late payment rates, discount uptake, and dog population distribution.  

*Note: Raw datasets from Waikato Open Data Co-Lab are used. Running the SQL scripts demonstrates the end-to-end workflow from raw data to analytical insights.*  
