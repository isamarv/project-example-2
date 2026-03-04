# Cerner Millennium Referral & Future Orders Data Extract

## Overview

This document explains the CCL scripts for extracting referral and order data from Cerner Millennium.

---

## CRITICAL: Understanding the Two Data Workflows

In integrated Cerner Millennium environments (ambulatory offices + acute hospitals), there are **TWO SEPARATE WORKFLOWS** for patient referrals/orders:

### Workflow 1: Referral Management (Specialist Referrals)
- **Data Location:** `referral` table
- **Use Case:** Sending patients to other providers (specialists)
- **Script:** `cerner_millennium_referral_extract.ccl`
- **What it captures:** Consult requests, specialist referrals, provider-to-provider transfers

### Workflow 2: Future Orders (Labs, Imaging, Diagnostics)
- **Data Location:** `orders` table (with FUTURE order status)
- **Use Case:** Labs, imaging (CT, MRI, X-ray), diagnostic tests
- **Script:** `cerner_millennium_future_orders_extract.ccl`
- **What it captures:** Lab orders, radiology orders, diagnostic tests

### Why This Matters

| Order Type | Goes Through Referral Table? | Goes Through Scheduling? |
|------------|------------------------------|--------------------------|
| Specialist consult | ✅ Yes | Sometimes |
| Lab order | ❌ No (Future Order) | Rarely |
| CT/MRI | ❌ No (Future Order) | Usually yes |
| X-ray | ❌ No (Future Order) | Rarely |
| Ultrasound | ❌ No (Future Order) | Sometimes |

**If you only run the referral extract, you will MISS all labs and most imaging orders!**

---

## Which Script Do You Need?

| Scope | Script(s) to Use |
|-------|------------------|
| Specialist referrals only | `cerner_millennium_referral_extract.ccl` |
| Labs and imaging only | `cerner_millennium_future_orders_extract.ccl` |
| All referrals + labs + imaging | **Both scripts** |

---

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

## Future Orders Extract (Labs/Imaging)

The `cerner_millennium_future_orders_extract.ccl` script captures orders that bypass the referral table.

### Key Fields in Future Orders Extract

| Field | Description |
|-------|-------------|
| `order_type` | Type of order |
| `activity_type` | Activity classification (RADIOLOGY, LABORATORY, etc.) |
| `clinical_category` | Clinical category of the service |
| `order_status` | Current status (FUTURE, ORDERED, PENDING, COMPLETED) |
| `future_order_flag` | Y/N indicator if this is a future order |
| `scheduling_exists` | Y/N indicator if order has been scheduled |
| `scheduling_status` | Status of appointment (if scheduled) |

### Activity Types Captured

The future orders script filters on these activity type meanings (code set 106):
- `RADIOLOGY` - Imaging orders
- `LABORATORY` - Lab orders
- `PATHOLOGY` - Pathology orders
- `CARDIOLOGY` - Cardiac diagnostics
- `GENERAL` - General diagnostics

**Note:** You may need to adjust these based on CHS's specific code set values.

### Linking Ambulatory to Acute

The script tracks both:
- **Originating Encounter** (`originating_encntr_id`) - The ambulatory visit where order was placed
- **Target Encounter** (`encntr_id`) - The hospital encounter where service is performed

---

## Combining Both Extracts

If you need a unified view, run both scripts and combine results. Key considerations:

1. **Referral Extract** - Contains `referral_id`, linked to scheduling via `referral_entity_reltn`
2. **Future Orders Extract** - Contains `order_id`, linked to scheduling via `sch_order`

The future orders script **excludes** orders that ARE linked to referrals to prevent duplicates:
```sql
AND NOT EXISTS (
    SELECT 1 FROM referral ref 
    WHERE ref.order_id = ord.order_id 
    AND ref.active_ind = 1
)
```

---

## Next Steps for CHS Call

Questions to ask CHS:

### For Referrals:
1. What are the specific values in `referral_status_cd` and their meanings?
2. What `referral_type_cd` values exist in their system?
3. How do they track visit/appointment types for referrals?
4. Are there any custom fields they use for referral categorization?

### For Future Orders (Labs/Imaging):
5. Confirm which `activity_type_cd` values (code set 106) are used for labs and imaging
6. What percentage of imaging orders go through scheduling vs. walk-in?
7. Are there any custom order statuses beyond FUTURE, ORDERED, PENDING, COMPLETED?
8. Do they use `originating_encntr_id` to track where ambulatory orders originated?

### For Scope Clarification:
9. What types of "referrals" does your analysis need to include?
   - Specialist referrals only?
   - Labs and imaging?
   - All of the above?
10. What date range and volume are we looking at?

---

## File Summary

| File | Purpose |
|------|---------|
| `cerner_millennium_referral_extract.ccl` | Specialist referrals (from referral table) |
| `cerner_millennium_future_orders_extract.ccl` | Labs/Imaging orders (from orders table) |
| `REFERRAL_EXTRACT_README.md` | This documentation |
