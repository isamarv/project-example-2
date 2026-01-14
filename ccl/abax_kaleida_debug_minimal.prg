/*******************************************************************************
 * Program: abax_kaleida_debug_minimal
 * Purpose: MINIMAL version for debugging - Add tables incrementally
 * 
 * INSTRUCTIONS:
 * 1. Run this query first to verify core tables work
 * 2. Uncomment table groups one at a time (see sections below)
 * 3. When query fails, the last uncommented section is the problem
 ******************************************************************************/

drop program abax_kaleida_debug_minimal go
create program abax_kaleida_debug_minimal

prompt
  "Output to File/Printer/MINE" = "MINE",
  "Days Back" = 365
with outdev, days_back

select into value($outdev)

  /* Core fields - always included */
  referral_id         = r.referral_id
 ,order_id            = ord.order_id
 ,order_date          = format(ord.orig_order_dt_tm, "MM-DD-YYYY;;Q")
 ,referral_status     = uar_get_code_display(r.referral_status_cd)
 ,encntr_id           = e.encntr_id
 ,person_id           = patient.person_id
 
  /* SECTION 1: Provider - uncomment when ready */
 ,ordering_physician  = trim(rfrom.name_full_formatted)

  /* SECTION 2: Patient Address - uncomment when ready */
; ,patient_city       = a.city
; ,patient_state      = uar_get_code_display(a.state_cd)
; ,patient_zip        = a.zipcode_key

  /* SECTION 3: Encounter Aliases - uncomment when ready */
; ,fin_nbr            = eaFIN.alias
; ,patient_mrn        = eaMRN.alias

  /* SECTION 4: Billing - uncomment when ready */
; ,insurance_plan     = hp.plan_name

  /* SECTION 5: Organizations - uncomment when ready */
; ,referring_org      = o.org_name
; ,referred_to_org    = o2.org_name

  /* SECTION 6: Scheduling - uncomment when ready */
; ,schedule_date      = format(sa.beg_dt_tm, "MM-DD-YYYY;;Q")

  /* SECTION 7: Charges - uncomment when ready */
; ,cpt_code           = cmCPT.field6

from
  /* CORE TABLES - Required */
  referral r,
  orders ord,
  order_catalog oc,
  prsnl rfrom,
  encounter e,
  person patient

  /* SECTION 2: Patient Address - uncomment when ready */
; ,address a

  /* SECTION 3: Encounter Aliases - uncomment when ready */
; ,encntr_alias eaFIN
; ,encntr_alias eaMRN

  /* SECTION 4: Billing - uncomment when ready */
; ,pft_encntr pe
; ,benefit_order bo
; ,bo_hp_reltn bhr
; ,health_plan hp

  /* SECTION 5: Organizations - uncomment when ready */
; ,organization o
; ,address a3
; ,organization o2
; ,address a2
; ,phone ph

  /* SECTION 6: Scheduling - uncomment when ready */
; ,referral_entity_reltn rer
; ,sch_event se
; ,sch_appt sa

  /* SECTION 7: Charges - uncomment when ready */
; ,order_action oa
; ,charge c
; ,charge_mod cmCPT
; ,charge_mod cmICD

/*******************************************************************************
 * CORE JOINS - These should always work
 ******************************************************************************/
plan r
  where r.active_ind = 1
    and r.order_id > 0
    and r.encntr_id > 0

join ord
  where ord.order_id = r.order_id
    and ord.orig_order_dt_tm >= cnvtdatetime(curdate - $days_back, 0)

join oc
  where oc.catalog_cd = ord.catalog_cd

join rfrom
  where rfrom.person_id = r.refer_from_provider_id

/* CRITICAL: Using encntr_id (not person_id) for specific encounter */
join e
  where e.encntr_id = r.encntr_id
    and e.active_ind = 1

join patient
  where patient.person_id = e.person_id
    and patient.active_ind = 1

/*******************************************************************************
 * SECTION 2: Patient Address - uncomment when ready
 ******************************************************************************/
/*
join a
  where a.parent_entity_id = outerjoin(patient.person_id)
    and a.parent_entity_name = outerjoin("PERSON")
    and a.active_ind = outerjoin(1)
    and a.address_type_seq = outerjoin(1)
*/

/*******************************************************************************
 * SECTION 3: Encounter Aliases - uncomment when ready
 ******************************************************************************/
/*
join eaFIN
  where eaFIN.encntr_id = e.encntr_id
    and eaFIN.active_ind = 1
    and eaFIN.encntr_alias_type_cd = 
        (select cv.code_value from code_value cv 
         where cv.code_set = 319 and cv.cdf_meaning = "FIN NBR" and cv.active_ind = 1)

join eaMRN
  where eaMRN.encntr_id = e.encntr_id
    and eaMRN.active_ind = 1
    and eaMRN.encntr_alias_type_cd = 
        (select cv.code_value from code_value cv 
         where cv.code_set = 319 and cv.cdf_meaning = "MRN" and cv.active_ind = 1)
*/

/*******************************************************************************
 * SECTION 4: Billing - uncomment when ready
 * NOTE: These tables may not exist in all Cerner instances!
 ******************************************************************************/
/*
join pe
  where pe.encntr_id = outerjoin(e.encntr_id)

join bo
  where bo.pft_encntr_id = outerjoin(pe.pft_encntr_id)

join bhr
  where bhr.benefit_order_id = outerjoin(bo.benefit_order_id)
    and bhr.priority_seq = outerjoin(1)

join hp
  where hp.health_plan_id = outerjoin(bhr.health_plan_id)
*/

/*******************************************************************************
 * SECTION 5: Organizations - uncomment when ready
 ******************************************************************************/
/*
join o
  where o.organization_id = outerjoin(r.refer_from_organization_id)

join a3
  where a3.parent_entity_id = outerjoin(o.organization_id)
    and a3.parent_entity_name = outerjoin("ORGANIZATION")
    and a3.active_ind = outerjoin(1)
    and a3.address_type_seq = outerjoin(1)

join o2
  where o2.organization_id = outerjoin(r.refer_to_organization_id)

join a2
  where a2.parent_entity_id = outerjoin(o2.organization_id)
    and a2.parent_entity_name = outerjoin("ORGANIZATION")
    and a2.active_ind = outerjoin(1)
    and a2.address_type_seq = outerjoin(1)

join ph
  where ph.parent_entity_id = outerjoin(o2.organization_id)
    and ph.parent_entity_name = outerjoin("ORGANIZATION")
    and ph.active_ind = outerjoin(1)
    and ph.phone_type_seq = outerjoin(1)
*/

/*******************************************************************************
 * SECTION 6: Scheduling - uncomment when ready
 ******************************************************************************/
/*
join rer
  where rer.referral_id = outerjoin(r.referral_id)
    and rer.parent_entity_name = outerjoin("SCH_EVENT")

join se
  where se.sch_event_id = outerjoin(rer.parent_entity_id)
    and se.active_ind = outerjoin(1)

join sa
  where sa.sch_event_id = outerjoin(se.sch_event_id)
    and sa.active_ind = outerjoin(1)
*/

/*******************************************************************************
 * SECTION 7: Charges - uncomment when ready
 ******************************************************************************/
/*
join oa
  where oa.order_id = outerjoin(ord.order_id)

join c
  where c.encntr_id = outerjoin(e.encntr_id)
    and c.order_id = outerjoin(ord.order_id)

join cmCPT
  where cmCPT.charge_item_id = outerjoin(c.charge_item_id)
    and cmCPT.active_ind = outerjoin(1)
    and cmCPT.field2_id = outerjoin(1)

join cmICD
  where cmICD.charge_item_id = outerjoin(c.charge_item_id)
    and cmICD.active_ind = outerjoin(1)
    and cmICD.field2_id = outerjoin(1)
*/

with nocounter, maxrec = 1000, time = 300

end
go
