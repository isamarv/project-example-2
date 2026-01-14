/*  ========================================================================
    Program:  abax_kaleida_poc_referral_extract_core
    Purpose:  Minimal referral/order extract intended for DVDev debugging.
              This version avoids billing/scheduling/charge dependencies and
              does NOT join encounter-related tables.

    Notes:
    - Returns one row per referral/order (distinct).
    - Patient is joined from referral.person_id.
    - Identifiers are anonymized in the same way as the full script.
    ======================================================================== */

drop program abax_kaleida_poc_referral_extract_core go
create program abax_kaleida_poc_referral_extract_core

prompt
  "Output to File/Printer/MINE" = "MINE",
  "Days Back" = 365
with outdev, days_back

select distinct into value(outdev)

  order_id = build(
      substring(1,3,cnvtstring(rand(0))),
      substring(textlen(cnvtstring(r.order_id)) - 3, 4, cnvtstring(r.order_id)),
      substring(1,3,cnvtstring(rand(0)))
  )

 ,referral_id = build(
      substring(1,3,cnvtstring(rand(0))),
      substring(textlen(cnvtstring(r.referral_id)) - 3, 4, cnvtstring(r.referral_id)),
      substring(1,3,cnvtstring(rand(0)))
  )

 ,order_date                  = format(ord.orig_order_dt_tm, "MM-DD-YYYY;Q")
 ,order_proc_code             = ord.catalog_cd
 ,order_proc_code_description = oc.primary_mnemonic
 ,referral_status             = uar_get_code_display(r.referral_status_cd)
 ,order_status                = uar_get_code_display(ord.order_status_cd)
 ,referral_class              = uar_get_code_display(ord.activity_type_cd)

 ,ordering_physician_name     = trim(rfrom.name_full_formatted)

 ,patient_gender              = uar_get_code_meaning(patient.sex_cd)
 ,patient_birth_year          = format(patient.birth_dt_tm, "YYYY;Q")
 ,patient_city                = a.city
 ,patient_state               = uar_get_code_display(a.state_cd)
 ,patient_zip                 = a.zipcode_key

from
  referral r,
  orders ord,
  order_catalog oc,
  prsnl rfrom,
  person patient,
  address a

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

join patient
  where patient.person_id = r.person_id
    and patient.birth_dt_tm != null

join a
  where a.parent_entity_id = patient.person_id
    and a.parent_entity_name = "PERSON"
    and a.active_ind = 1
    and a.address_type_seq = 1

with nocounter, maxrec=500000, time=600, format(date,";q")

end
go
