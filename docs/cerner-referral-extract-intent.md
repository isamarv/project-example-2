# Cerner CCL Referral Extract — intent, assumptions, and debugging notes

## Intent (what the script is trying to do)
This CCL is intended to produce a **referral intelligence extract** for AbaxHealth Insight, with one record per referral/order (subject to data availability), including:

- **Referral & order metadata**: referral status, order status, order date, procedure/catalog, expiration date
- **Patient demographics**: birth year, sex, address (city/state/zip)
- **Identifiers (anonymized)**: MRN, FIN, order_id, referral_id (randomized prefixes/suffixes)
- **Referring / referred-to organizations**: org names + address/phone (when present)
- **Scheduling context**: latest patient appointment for the referral’s scheduling event (when present)
- **Insurance context**: primary plan name + financial class (when present)
- **Clinical/billing codes**: charge description + CPT/ICD (when present)

## Why the client is seeing “CRM perform error”
In Cerner, **table/view availability differs by domain, Millennium version, and local build**. A “perform error” frequently occurs when:

- A table/view in the `FROM` list **does not exist** in that environment (common with billing/PM tables such as `PFT_ENCNTR`, or site-specific scheduling/charge structures)
- A join references a **column that doesn’t exist** in that environment
- A subquery/outerjoin pattern is incompatible with that site’s object definitions

Because CCL compilation/execution fails at parse/resolve time, **you cannot reliably “outerjoin away” a missing table**. The only practical approach is:

- Start from a minimal working query
- Add join blocks back one at a time to identify which table/view (or column) is not supported in that instance

## Key client concern: `join encounter e where r.person_id = e.person_id`
The client is correct: joining `encounter` by `person_id` can be extremely expansive.

- A patient can have **many encounters**
- Joining `referral` to **all** encounters for that person causes:
  - Duplicate rows per referral/order
  - Unnecessary I/O and poor performance
  - Unclear semantics (which encounter is “the” encounter for the referral?)

### Recommended fix (anchor encounter to the order context)
In most Cerner builds, `ORDERS` carries `ENCNTR_ID`. If your goal is to pull encounter-linked data (FIN, insurance, charges, admit date), the safer join is:

- Join `encounter` using `ord.encntr_id` (or the referral’s encounter id if your domain stores one)
- If an order truly has no encounter, decide whether you want to **drop the row** (inner join) or keep it with nulls (outer join)

This addresses the “overkill” concern because you only pull the **single encounter that the order is tied to**, rather than all encounters for a person.

## Practical debugging approach for DVDev
Use an incremental build:

- **Step A (core)**: `referral` → `orders` → `order_catalog` → `person` (+ patient address)
- **Step B (encounter)**: add `encounter` joined on `ord.encntr_id`
- **Step C (aliases)**: add `encntr_alias` (FIN/MRN) joined on `e.encntr_id`
- **Step D (insurance)**: add `pft_encntr` → `benefit_order` → `bo_hp_reltn` → `health_plan`
- **Step E (scheduling)**: add `referral_entity_reltn` → `sch_event` → `sch_appt`
- **Step F (charges/codes)**: add `order_action` → `charge` → `charge_mod`

If the query fails immediately after adding a block, the first table in that block is the most likely missing/unsupported object.

## Suggested response language to the client (pasteable)
> The intent of the script is to produce a referral/order level extract for referral intelligence: referral/order metadata plus optional enrichment (encounter-linked FIN/MRN, insurance, scheduling, referring/referred-to org, and charge/coding).  
>  
> You’re right to call out the `encounter` join by `person_id`; that can return all encounters for a patient and will duplicate rows and degrade performance. We’re updating the logic to anchor encounter selection to the order (`ord.encntr_id`) so the query only pulls the encounter associated with the order/referral context.  
>  
> Regarding the perform error: Cerner environments can differ in available billing/scheduling/charge tables. To isolate the unsupported object(s), we can start from a minimal referral→orders→person extract and add the enrichment joins back one section at a time until the error appears.
