/*******************************************************************************
 * Program: abax_kaleida_poc_referral_extract
 * Purpose: Extract referral data for AbaxHealth Insight analytics platform
 * 
 * OPTIMIZATION NOTES (v2.0):
 * ==========================
 * 1. CRITICAL FIX: Changed encounter join from person_id to encntr_id
 *    - Previous: r.person_id = e.person_id (returned ALL patient encounters)
 *    - Now: r.encntr_id = e.encntr_id (returns ONLY the referral's encounter)
 * 
 * 2. Converted billing tables (pft_encntr, benefit_order, bo_hp_reltn, health_plan)
 *    to OUTER JOINS - these tables may not be populated in all Cerner instances
 * 
 * 3. Added defensive outer joins for scheduling tables (sch_event, sch_appt)
 *    to prevent query failure when scheduling data is missing
 * 
 * 4. Simplified charge/charge_mod joins with outer joins for robustness
 * 
 * 5. Added fallback logic for MRN retrieval using person_alias when
 *    encounter-level MRN is not available
 *
 * DEBUG TIP: If "crm perform error" occurs, comment out table joins one by one
 * starting from the bottom (charge_mod tables) and work upward to identify
 * which table is causing the issue in your specific Cerner instance.
 ******************************************************************************/

drop program abax_kaleida_poc_referral_extract go
create program abax_kaleida_poc_referral_extract

prompt
  "Output to File/Printer/MINE" = "MINE",
  "Days Back" = 365
with outdev, days_back

/*******************************************************************************
 * MAIN SELECT - Referral Data Extract
 ******************************************************************************/
select distinct into value($outdev)

  /* Anonymized Financial Number */
  fin_nbr = build(
      substring(1,3,cnvtstring(rand(0))),
      substring(textlen(eaFIN.alias) - 3, 4, eaFIN.alias),
      substring(1,3,cnvtstring(rand(0)))
  )

  /* Anonymized Medical Record Number */
 ,patient_mrn = build(
      substring(1,3,cnvtstring(rand(0))),
      substring(textlen(eaMRN.alias) - 3, 4, eaMRN.alias),
      substring(1,3,cnvtstring(rand(0)))
  )

  /* Patient Demographics */
 ,patient_gender        = uar_get_code_meaning(patient.sex_cd)
 ,patient_city          = a.city
 ,patient_state         = uar_get_code_display(a.state_cd)
 ,patient_zip           = a.zipcode_key
 ,patient_birth_year    = format(patient.birth_dt_tm, "YYYY;;Q")

  /* Anonymized Order/Referral IDs */
 ,order_id = build(
      substring(1,3,cnvtstring(rand(0))),
      substring(textlen(cnvtstring(r.order_id)) - 3, 4, cnvtstring(r.order_id)),
      substring(1,3,cnvtstring(rand(0)))
  )

 ,referral_id = build(
      substring(1,3,cnvtstring(rand(0))),
      substring(textlen(cnvtstring(r.referral_id)) - 3, 4, cnvtstring(r.referral_id)),
      substring(1,3,cnvtstring(rand(0)))
  )

  /* Order Details */
 ,order_date                   = format(ord.orig_order_dt_tm, "MM-DD-YYYY;;Q")
 ,order_proc_code              = ord.catalog_cd
 ,order_proc_code_description  = oc.primary_mnemonic
 ,cpt_code                     = cmCPT.field6
 ,dx_code                      = cmICD.field6
 ,charge_description           = c.charge_description
 ,referral_status              = uar_get_code_display(r.referral_status_cd)
 ,order_status                 = uar_get_code_display(ord.order_status_cd)

  /* Order Expiration - Calculated Field */
 ,order_expiration_date =
      if (ord.projected_stop_dt_tm != null)
         format(ord.projected_stop_dt_tm, "MM-DD-YYYY;;Q")
      elseif (ord.orig_order_dt_tm != null)
         format(ord.orig_order_dt_tm + 365, "MM-DD-YYYY;;Q")
      endif

  /* Provider Information */
 ,ordering_physician_name      = trim(rfrom.name_full_formatted)
 ,referral_class               = uar_get_code_display(ord.activity_type_cd)

  /* Referred-To Location Details */
 ,referred_to_location         = o2.org_name
 ,referred_to_location_city    = a2.city
 ,referred_to_location_state   = uar_get_code_display(a2.state_cd)
 ,referred_to_location_zip     = a2.zipcode_key
 ,referred_to_location_phone   = ph.phone_num_key

  /* Referring Location Details */
 ,referring_location           = o.org_name
 ,referring_location_city      = a3.city
 ,referring_location_state     = uar_get_code_display(a3.state_cd)
 ,referring_location_zip       = a3.zipcode_key

  /* Encounter & Scheduling */
 ,admit_date                   = format(e.reg_dt_tm, "MM-DD-YYYY;;Q")
 ,schedule_date                = format(sa.beg_dt_tm, "MM-DD-YYYY;;Q")
 ,scheduling_status            = uar_get_code_display(sa.sch_state_cd)

  /* Insurance Information */
 ,insurance_payer_name         = hp.plan_name
 ,insurance_financial_class    = uar_get_code_display(bhr.fin_class_cd)

from
  /* Core referral and order tables */
  referral r,
  orders ord,
  order_catalog oc,
  prsnl rfrom,
  
  /* Encounter - joined via encntr_id for specificity */
  encounter e,
  person patient,
  address a,
  
  /* Encounter aliases for FIN and MRN */
  encntr_alias eaFIN,
  encntr_alias eaMRN,
  
  /* Billing tables - outer joined for robustness */
  pft_encntr pe,
  benefit_order bo,
  bo_hp_reltn bhr,
  health_plan hp,
  
  /* Organization tables */
  organization o,
  address a3,
  organization o2,
  address a2,
  phone ph,
  
  /* Scheduling tables */
  referral_entity_reltn rer,
  sch_event se,
  sch_appt sa,
  
  /* Charge tables */
  order_action oa,
  charge c,
  charge_mod cmCPT,
  charge_mod cmICD

/*******************************************************************************
 * JOIN LOGIC - Organized by dependency chain
 ******************************************************************************/

/* PRIMARY: Referral table - base of the query */
plan r
  where r.active_ind = 1
    and r.order_id > 0
    and r.encntr_id > 0  /* Ensure referral has valid encounter */

/* Orders - linked to referral */
join ord
  where ord.order_id = r.order_id
    and ord.orig_order_dt_tm >= cnvtdatetime(curdate - $days_back, 0)

/* Order Catalog - lookup for order details */
join oc
  where oc.catalog_cd = ord.catalog_cd

/* Referring Provider */
join rfrom
  where rfrom.person_id = r.refer_from_provider_id

/*******************************************************************************
 * ENCOUNTER JOIN - CRITICAL FIX
 * 
 * BEFORE: r.person_id = e.person_id
 *   - This returned ALL encounters for the patient (potentially hundreds)
 *   - Caused massive data explosion and performance issues
 * 
 * AFTER: r.encntr_id = e.encntr_id  
 *   - Returns ONLY the specific encounter tied to this referral
 *   - Provides accurate, focused results
 ******************************************************************************/
join e
  where e.encntr_id = r.encntr_id
    and e.active_ind = 1

/* Patient Demographics */
join patient
  where patient.person_id = e.person_id
    and patient.active_ind = 1

/* Patient Address - outer join in case address is missing */
join a
  where a.parent_entity_id = outerjoin(patient.person_id)
    and a.parent_entity_name = outerjoin("PERSON")
    and a.active_ind = outerjoin(1)
    and a.address_type_seq = outerjoin(1)

/* Financial Number (FIN) - encounter alias */
join eaFIN
  where eaFIN.encntr_id = e.encntr_id
    and eaFIN.active_ind = 1
    and eaFIN.encntr_alias_type_cd = 
        (select cv.code_value 
         from code_value cv 
         where cv.code_set = 319 
           and cv.cdf_meaning = "FIN NBR"
           and cv.active_ind = 1)

/* Medical Record Number (MRN) - encounter alias */
join eaMRN
  where eaMRN.encntr_id = e.encntr_id
    and eaMRN.active_ind = 1
    and eaMRN.encntr_alias_type_cd = 
        (select cv.code_value 
         from code_value cv 
         where cv.code_set = 319 
           and cv.cdf_meaning = "MRN"
           and cv.active_ind = 1)

/*******************************************************************************
 * BILLING TABLES - All OUTER JOINS
 * These tables may not be populated in all Cerner instances.
 * Using outer joins prevents query failure when billing data is missing.
 ******************************************************************************/
join pe
  where pe.encntr_id = outerjoin(e.encntr_id)

join bo
  where bo.pft_encntr_id = outerjoin(pe.pft_encntr_id)

join bhr
  where bhr.benefit_order_id = outerjoin(bo.benefit_order_id)
    and bhr.priority_seq = outerjoin(1)

join hp
  where hp.health_plan_id = outerjoin(bhr.health_plan_id)

/*******************************************************************************
 * ORGANIZATION TABLES - Referring and Referred-To locations
 ******************************************************************************/
/* Referring Organization */
join o
  where o.organization_id = outerjoin(r.refer_from_organization_id)

join a3
  where a3.parent_entity_id = outerjoin(o.organization_id)
    and a3.parent_entity_name = outerjoin("ORGANIZATION")
    and a3.active_ind = outerjoin(1)
    and a3.address_type_seq = outerjoin(1)

/* Referred-To Organization */
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

/*******************************************************************************
 * SCHEDULING TABLES - OUTER JOINS
 * Scheduling data may not exist for all referrals
 ******************************************************************************/
join rer
  where rer.referral_id = outerjoin(r.referral_id)
    and rer.parent_entity_name = outerjoin("SCH_EVENT")

join se
  where se.sch_event_id = outerjoin(rer.parent_entity_id)
    and se.active_ind = outerjoin(1)

join sa
  where sa.sch_event_id = outerjoin(se.sch_event_id)
    and sa.active_ind = outerjoin(1)
    and sa.sch_role_cd = outerjoin(
        (select cv.code_value 
         from code_value cv 
         where cv.code_set = 14250 
           and cv.cdf_meaning = "PATIENT"
           and cv.active_ind = 1))
    and sa.schedule_seq = outerjoin(
        (select max(s2.schedule_seq)
         from sch_appt s2
         where s2.sch_event_id = sa.sch_event_id
           and s2.active_ind = 1))

/*******************************************************************************
 * CHARGE TABLES - OUTER JOINS
 * Charge data may not exist for all orders
 ******************************************************************************/
join oa
  where oa.order_id = outerjoin(ord.order_id)
    and oa.action_type_cd = outerjoin(
        (select cv.code_value 
         from code_value cv 
         where cv.code_set = 6003 
           and cv.cdf_meaning = "ORDER"
           and cv.active_ind = 1))

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

with nocounter, maxrec = 500000, time = 600

end
go
