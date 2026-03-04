# Cerner Millennium Referral Data Extract

## Overview

This document explains the CCL script for extracting referral data from Cerner Millennium, addressing the two key concerns raised by the team.

---

## Team Concern #1: Visit Type Identification

The original script was missing fields to identify what the referral is for. The following fields have been added:

| Field Name | Source | Description |
|------------|--------|-------------|
| `referral_type` | `r.referral_type_cd` | The explicit type of referral (e.g., Consult, Procedure, Diagnostic) |
| `encounter_type` | `e.encntr_type_cd` | The type of encounter/visit (e.g., Outpatient, Inpatient, Emergency) |
| `encounter_type_class` | `e.encntr_type_class_cd` | Classification of the encounter type |
| `referral_reason` | `r.reason_for_referral` | Free-text reason for the referral |
| `service_category` | `ord.dcp_clin_cat_cd` | Clinical category of the service |
| `referral_class` | `ord.activity_type_cd` | Activity type from the order |
| `catalog_type` | `ord.catalog_type_cd` | Catalog type classification |

**Recommendation:** To determine which field best identifies the "visit type" in your specific CHS environment, run a sample query on these fields and review the distinct values with the CHS team.

---

## Team Concern #2: Understanding the 3 Statuses

The script contains three distinct status fields, each tracking a different stage of the referral workflow:

### Status 1: `referral_status_cd`
- **Source:** `referral.referral_status_cd`
- **Purpose:** Tracks the status of the referral record itself
- **Common Values:**
  - Pending
  - Approved
  - Denied
  - In Progress
  - Completed
  - Cancelled

### Status 2: `order_status_cd`
- **Source:** `orders.order_status_cd`
- **Purpose:** Tracks the status of the clinical order associated with the referral
- **Common Values:**
  - Ordered
  - Pending
  - In Progress
  - Completed
  - Discontinued
  - Canceled

### Status 3: `scheduling_status`
- **Source:** `sch_appt.sch_state_cd`
- **Purpose:** Tracks the status of any scheduled appointment linked to the referral
- **Common Values:**
  - Scheduled
  - Confirmed
  - Rescheduled
  - Checked-In
  - Completed
  - No-Show
  - Cancelled

**Key Point:** These statuses are NOT redundant - they track different lifecycle stages:
1. Was the referral approved? → `referral_status_cd`
2. Is the clinical order active? → `order_status_cd`
3. Did the patient show up? → `scheduling_status`

---

## Key Fixes in Millennium Version

### 1. MRN Lookup Corrected
**Original (Incorrect):**
```sql
-- Used encntr_alias with code set 319 for MRN
AND eaMRN.encntr_alias_type_cd = value(uar_get_code_by("MEANING",319,"MRN"))
```

**Corrected:**
```sql
-- MRN is in person_alias with code set 4
LEFT JOIN person_alias pa_mrn ON r.person_id = pa_mrn.person_id
    AND pa_mrn.person_alias_type_cd = value(uar_get_code_by('MEANING', 4, 'MRN'))
```

### 2. Consistent JOIN Syntax
- All joins converted to explicit LEFT JOIN syntax
- Prevents data loss from implicit INNER JOINs in WHERE clause

### 3. Proper Encounter Linking
- Uses `r.encntr_id` instead of just `r.person_id` for accurate encounter association

### 4. ICD Code Update
- Added support for both ICD9 and ICD10 codes:
```sql
AND cv.cdf_meaning IN ("ICD9", "ICD10")
```

### 5. Added Provider NPI
- Included NPI lookup for referring provider

---

## Code Set Reference

For CHS to provide status value documentation, request lookups on these code sets:

| Code Set | Field | Description |
|----------|-------|-------------|
| 14149 | `referral_status_cd` | Referral status values |
| 6004 | `order_status_cd` | Order status values |
| 14232 | `sch_state_cd` | Scheduling state values |
| 71 | `encntr_type_cd` | Encounter types |
| 106 | `activity_type_cd` | Activity types |

**Sample Query to Get Code Values:**
```sql
SELECT cv.code_value, cv.display, cv.description, cv.cdf_meaning
FROM code_value cv
WHERE cv.code_set = 14149  -- Change to desired code set
AND cv.active_ind = 1
ORDER BY cv.display
```

---

## Environment Notes

### CommunityWorks vs Millennium

Both environments use CCL and share the same core data model. Key differences:

| Aspect | CommunityWorks | Millennium |
|--------|----------------|------------|
| Hosting | Cloud/Hosted by Cerner | On-premise or hosted |
| Customization | Limited | Extensive |
| Table Structure | Standard | May have custom extensions |
| Code Sets | Standard | May have custom values |

The provided script should work in both environments, but code set values may differ. Always validate against the specific environment's data dictionary.

---

## Usage

1. Update the date range in the WHERE clause:
```sql
AND r.create_dt_tm BETWEEN cnvtdatetime("01-DEC-2025 00:00:00") 
                       AND cnvtdatetime("31-DEC-2025 23:59:59")
```

2. Add output file specification if needed:
```sql
SELECT INTO "your_output_file.csv"
```

3. Adjust `maxrec` and `time` parameters based on expected data volume

---

## Next Steps for CHS Call

Questions to ask CHS:
1. What are the specific values in `referral_status_cd` and their meanings?
2. What `referral_type_cd` values exist in their system?
3. How do they track visit/appointment types for referrals?
4. Are there any custom fields they use for referral categorization?
