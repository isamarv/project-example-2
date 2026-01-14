# Cerner Referral Extract - Optimization Notes

## Overview

This document explains the optimizations made to the `abax_kaleida_poc_referral_extract` CCL script to address the "crm perform error" and improve query performance.

## Critical Issue Fixed: Encounter Join

### The Problem

The original query contained this join logic:

```sql
join e
  where r.person_id = e.person_id
    and e.active_ind = 1
```

**This was the "overkill" the client identified.** This join linked referrals to encounters using only `person_id`, which means:
- Every referral would return **ALL active encounters** for that patient
- A patient with 50 historical encounters would generate 50 rows per referral
- This caused massive data explosion and potential query timeouts

### The Fix

```sql
join e
  where e.encntr_id = r.encntr_id
    and e.active_ind = 1
```

The referral table has an `encntr_id` field that directly links to the **specific encounter** where the referral was created. Using this field returns exactly one encounter per referral.

## Changes Summary

### 1. Encounter Join (CRITICAL)
- **Before**: `r.person_id = e.person_id` (ALL patient encounters)
- **After**: `r.encntr_id = e.encntr_id` (specific referral encounter)

### 2. Billing Tables → Outer Joins
The following tables are now **outer joined** because they may not exist in all Cerner instances:
- `pft_encntr` (PE)
- `benefit_order` (BO)
- `bo_hp_reltn` (BHR)
- `health_plan` (HP)

**Why?** Not all organizations use Cerner's billing module. Inner joins on these tables will cause the query to return zero results or throw errors if the tables are empty.

### 3. Scheduling Tables → Outer Joins
- `referral_entity_reltn`
- `sch_event`
- `sch_appt`

**Why?** Not all referrals have associated scheduling events.

### 4. Charge Tables → Outer Joins
- `order_action`
- `charge`
- `charge_mod` (both CPT and ICD)

**Why?** Charges may not exist for all orders, especially for outpatient referrals.

### 5. Patient Address → Outer Join
Changed to outer join to handle patients without address records.

### 6. Code Value Lookups
Changed from `uar_get_code_by()` to subqueries for better cross-platform compatibility:

```sql
-- Before
and eaFIN.encntr_alias_type_cd in (
    value(uar_get_code_by("MEANING",319,"FIN NBR")),
    value(uar_get_code_by("DISPLAYKEY",319,"FINNBR"))
)

-- After  
and eaFIN.encntr_alias_type_cd = 
    (select cv.code_value 
     from code_value cv 
     where cv.code_set = 319 
       and cv.cdf_meaning = "FIN NBR"
       and cv.active_ind = 1)
```

## Debugging Guide

If you still encounter "crm perform error", follow this systematic debugging approach:

### Step 1: Start with Core Tables Only

```sql
select count(*) 
from referral r, orders ord, order_catalog oc, prsnl rfrom, encounter e
plan r
  where r.active_ind = 1 and r.order_id > 0 and r.encntr_id > 0
join ord
  where ord.order_id = r.order_id
join oc
  where oc.catalog_cd = ord.catalog_cd
join rfrom
  where rfrom.person_id = r.refer_from_provider_id
join e
  where e.encntr_id = r.encntr_id and e.active_ind = 1
with nocounter
```

### Step 2: Add Tables One at a Time

Add each table group in this order and test:

1. **Patient + Address**
2. **Encounter Aliases** (eaFIN, eaMRN)
3. **Billing tables** (pe, bo, bhr, hp)
4. **Organization tables** (o, o2, a2, a3, ph)
5. **Scheduling tables** (rer, se, sa)
6. **Charge tables** (oa, c, cmCPT, cmICD)

### Step 3: Check Table Existence

Run this to verify tables exist in your DVDev instance:

```sql
select distinct t.table_name
from all_tables t
where t.table_name in (
  'REFERRAL', 'ORDERS', 'ORDER_CATALOG', 'PRSNL', 'ENCOUNTER',
  'PERSON', 'ADDRESS', 'ENCNTR_ALIAS', 'PFT_ENCNTR', 'BENEFIT_ORDER',
  'BO_HP_RELTN', 'HEALTH_PLAN', 'ORGANIZATION', 'PHONE',
  'REFERRAL_ENTITY_RELTN', 'SCH_EVENT', 'SCH_APPT',
  'ORDER_ACTION', 'CHARGE', 'CHARGE_MOD'
)
```

### Step 4: Verify Data Exists

Check if tables have data:

```sql
select "REFERRAL" as tablename, count(*) as cnt from referral where active_ind = 1 with nocounter
union all
select "PFT_ENCNTR", count(*) from pft_encntr with nocounter
union all
select "BENEFIT_ORDER", count(*) from benefit_order with nocounter
union all
select "CHARGE", count(*) from charge with nocounter
```

## DVDev-Specific Notes

If running in DVDev (Development/Test environment):

1. **Limited Data**: DVDev instances may have limited or no data in certain tables
2. **Missing Tables**: Some tables may not be deployed to DVDev
3. **Code Values**: Code set values (319, 14250, 6003) may differ between environments

## Output Fields Reference

| Field | Source | Description |
|-------|--------|-------------|
| `fin_nbr` | encntr_alias | Anonymized Financial Number |
| `patient_mrn` | encntr_alias | Anonymized Medical Record Number |
| `patient_gender` | person.sex_cd | Patient gender |
| `patient_city/state/zip` | address | Patient address |
| `patient_birth_year` | person.birth_dt_tm | Birth year only (anonymized) |
| `order_id` | referral.order_id | Anonymized order ID |
| `referral_id` | referral.referral_id | Anonymized referral ID |
| `order_date` | orders.orig_order_dt_tm | Original order date |
| `order_proc_code` | orders.catalog_cd | Procedure catalog code |
| `cpt_code` | charge_mod.field6 | CPT code |
| `dx_code` | charge_mod.field6 | ICD diagnosis code |
| `referral_status` | referral.referral_status_cd | Current referral status |
| `order_status` | orders.order_status_cd | Current order status |
| `ordering_physician_name` | prsnl.name_full_formatted | Referring provider name |
| `referred_to_location` | organization.org_name | Destination facility |
| `referring_location` | organization.org_name | Source facility |
| `admit_date` | encounter.reg_dt_tm | Registration date |
| `schedule_date` | sch_appt.beg_dt_tm | Scheduled appointment date |
| `scheduling_status` | sch_appt.sch_state_cd | Appointment status |
| `insurance_payer_name` | health_plan.plan_name | Insurance plan name |
| `insurance_financial_class` | bo_hp_reltn.fin_class_cd | Financial class |

## Contact

For additional support or questions about this script, contact the AbaxHealth technical team.
