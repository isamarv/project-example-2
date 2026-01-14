/*  ========================================================================
    Program:  abax_kaleida_poc_referral_extract_full
    Purpose:  Referral intelligence extract for AbaxHealth Insight.

    Important join correction (performance + semantics):
    - This script anchors encounter using ORDERS.ENCNTR_ID, rather than joining
      ENCOUNTER by PERSON_ID (which can bring back all encounters for a patient).

    Environment variability:
    - Some Cerner instances may not expose all billing/scheduling/charge tables.
      If you see a "perform error", run the CORE program first and then add
      join blocks incrementally.
    ======================================================================== */

drop program abax_kaleida_poc_referral_extract_full go
create program abax_kaleida_poc_referral_extract_full

prompt
  "Output to File/Printer/MINE" = "MINE",
  "Days Back" = 365
with outdev, days_back

select distinct into value(outdev)

  fin_nbr = build(
      substring(1,3,cnvtstring(rand(0))),
      substring(textlen(eaFIN.alias) - 3, 4, eaFIN.alias),
      substring(1,3,cnvtstring(rand(0)))
  )

 ,patient_mrn = build(
      substring(1,3,cnvtstring(rand(0))),
      substring(textlen(eaMRN.alias) - 3, 4, eaMRN.alias),
      substring(1,3,cnvtstring(rand(0)))
  )

 ,patient_gender        = uar_get_code_meaning(patient.sex_cd)
 ,patient_city          = a.city
 ,patient_state         = uar_get_code_display(a.state_cd)
 ,patient_zip           = a.zipcode_key
 ,patient_birth_year    = format(patient.birth_dt_tm, "YYYY;Q")

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

 ,order_date                   = format(ord.orig_order_dt_tm, "MM-DD-YYYY;Q")
 ,order_proc_code              = ord.catalog_cd
 ,order_proc_code_description  = oc.primary_mnemonic
 ,cpt_code                     = cmCPT.field6
 ,dx_code                      = cmICD.field6
 ,charge_description           = c.charge_description
 ,referral_status              = uar_get_code_display(r.referral_status_cd)
 ,order_status                 = uar_get_code_display(ord.order_status_cd)

 ,order_expiration_date =
      if (ord.projected_stop_dt_tm != null)
         format(ord.projected_stop_dt_tm, "MM-DD-YYYY;Q")
      elseif (ord.orig_order_dt_tm != null)
         format(ord.orig_order_dt_tm + 365, "MM-DD-YYYY;Q")
      endif

 ,ordering_physician_name      = trim(rfrom.name_full_formatted)
 ,referral_class               = uar_get_code_display(ord.activity_type_cd)

 ,referred_to_location         = o2.org_name
 ,referred_to_location_city    = a2.city
 ,referred_to_location_state   = uar_get_code_display(a2.state_cd)
 ,referred_to_location_zip     = a2.zipcode_key
 ,referred_to_location_phone   = ph.phone_num_key

 ,referring_location           = o.org_name
 ,referring_location_city      = a3.city
 ,referring_location_state     = uar_get_code_display(a3.state_cd)
 ,referring_location_zip       = a3.zipcode_key

 ,admit_date                   = format(e.beg_dt_tm, "MM-DD-YYYY;Q")
 ,schedule_date                = format(sa.beg_dt_tm, "MM-DD-YYYY;Q")
 ,scheduling_status            = uar_get_code_display(sa.sch_state_cd)

 ,insurance_payer_name         = hp.plan_name
 ,insurance_financial_class    = uar_get_code_display(bhr.fin_class_cd)

from
  referral r,
  orders ord,
  order_catalog oc,
  prsnl rfrom,
  person patient,
  address a,
  encounter e,
  encntr_alias eaFIN,
  encntr_alias eaMRN,
  pft_encntr pe,
  benefit_order bo,
  bo_hp_reltn bhr,
  health_plan hp,
  organization o,
  address a3,
  organization o2,
  address a2,
  phone ph,
  referral_entity_reltn rer,
  sch_event se,
  sch_appt sa,
  order_action oa,
  charge c,
  charge_mod cmCPT,
  charge_mod cmICD

plan r
  where r.active_ind = 1
    and r.order_id > 0

join ord
  where ord.order_id = r.order_id
    and ord.orig_order_dt_tm >= (sysdate - days_back)

join oc
  where oc.catalog_cd = ord.catalog_cd

join rfrom
  where r.refer_from_provider_id = rfrom.person_id

/* Patient should be anchored by the referral person_id */
join patient
  where patient.person_id = r.person_id
    and patient.birth_dt_tm != null

join a
  where a.parent_entity_id = patient.person_id
    and a.parent_entity_name = "PERSON"
    and a.active_ind = 1
    and a.address_type_seq = 1

/* Critical change: encounter anchored to the ORDER's encounter */
join e
  where e.encntr_id = ord.encntr_id
    and e.active_ind = 1

join eaFIN
  where eaFIN.encntr_id = e.encntr_id
    and eaFIN.active_ind = 1
    and sysdate between eaFIN.beg_effective_dt_tm and eaFIN.end_effective_dt_tm
    and eaFIN.encntr_alias_type_cd in
      (
        value(uar_get_code_by("MEANING",319,"FIN NBR")),
        value(uar_get_code_by("DISPLAYKEY",319,"FINNBR"))
      )

join eaMRN
  where eaMRN.encntr_id = e.encntr_id
    and eaMRN.active_ind = 1
    and sysdate between eaMRN.beg_effective_dt_tm and eaMRN.end_effective_dt_tm
    and eaMRN.encntr_alias_type_cd in
      (
        value(uar_get_code_by("MEANING",319,"MRN")),
        value(uar_get_code_by("DISPLAYKEY",319,"MRN"))
      )

join pe
  where pe.encntr_id = e.encntr_id

join bo
  where bo.pft_encntr_id = pe.pft_encntr_id

join bhr
  where bhr.benefit_order_id = bo.benefit_order_id
    and bhr.priority_seq = 1

join hp
  where hp.health_plan_id = bhr.health_plan_id

join o
  where o.organization_id = outerjoin(r.refer_from_organization_id)

join a3
  where a3.parent_entity_id = outerjoin(o.organization_id)
    and a3.parent_entity_name = "ORGANIZATION"
    and a3.active_ind = 1
    and a3.address_type_seq = 1

join o2
  where o2.organization_id = outerjoin(r.refer_to_organization_id)

join a2
  where a2.parent_entity_id = outerjoin(o2.organization_id)
    and a2.parent_entity_name = "ORGANIZATION"
    and a2.active_ind = 1
    and a2.address_type_seq = 1

join ph
  where ph.parent_entity_id = outerjoin(o2.organization_id)
    and ph.parent_entity_name = "ORGANIZATION"
    and ph.active_ind = 1
    and ph.phone_type_seq = 1

join rer
  where rer.referral_id = outerjoin(r.referral_id)
    and rer.parent_entity_name = "SCH_EVENT"

join se
  where se.sch_event_id = outerjoin(rer.parent_entity_id)
    and se.active_ind = 1
    and sysdate between se.beg_effective_dt_tm and se.end_effective_dt_tm

join sa
  where sa.sch_event_id = outerjoin(se.sch_event_id)
    and sa.active_ind = 1
    and sa.sch_role_cd = value(uar_get_code_by('MEANING',14250,'PATIENT'))
    and sa.schedule_seq =
      (
        select max(s2.schedule_seq)
        from sch_appt s2
        where s2.sch_event_id = sa.sch_event_id
      )

join oa
  where oa.order_id = outerjoin(ord.order_id)

join c
  where c.encntr_id = outerjoin(ord.encntr_id)
    and c.ord_phys_id = outerjoin(oa.order_provider_id)

join cmCPT
  where cmCPT.charge_item_id = outerjoin(c.charge_item_id)
    and cmCPT.active_ind = 1
    and cmCPT.field2_id = 1

join cmICD
  where cmICD.charge_item_id = outerjoin(c.charge_item_id)
    and cmICD.active_ind = 1
    and cmICD.field2_id = 1

with nocounter, maxrec=500000, time=600, format(date,";q")

end
go
