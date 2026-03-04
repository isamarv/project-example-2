# Email Draft: CHS Referral Data Architecture Meeting

---

**To:** [CHS Team]

**Subject:** Referral & Future Orders Data Extract - Architecture Discovery Session

---

Hi [CHS Team],

I hope this message finds you well. We're looking to schedule a working session with your team to properly structure our referral data extract based on your Cerner Millennium environment.

## Background

Based on our initial review and conversations, we understand that your integrated ambulatory/acute environment has two distinct workflows for patient referrals and orders:

1. **Referral Management** – Used for specialist referrals (captured in the `referral` table)
2. **Future Orders** – Used for labs, imaging, and diagnostics (captured in the `orders` table at the patient level)

We want to ensure our data extract accurately captures both workflows according to how your system is configured.

## Meeting Objectives

During our session, we'd like to:

1. **Validate the data architecture** – Confirm how referrals vs. future orders flow through your system
2. **Review key code sets** – Understand the specific values used in your environment for:
   - Referral status codes (what each status means in your workflow)
   - Referral type codes (to identify what the referral is for)
   - Activity type codes at the order catalog level (to filter labs vs. imaging)
   - Order status codes
3. **Identify visit/order types** – Determine the best fields to categorize what each referral or order is for
4. **Discuss scheduling integration** – Understand which orders go through scheduling (CT, MRI) vs. walk-in (labs)
5. **Define scope** – Confirm what data is needed (date ranges, order types, statuses)

## Questions We'd Like to Discuss

### Referral Workflow:
- What values exist in `referral_status_cd` and what does each status represent in your workflow?
- How do you identify the type/purpose of a referral (consult type, specialty, etc.)?

### Future Orders (Labs/Imaging):
- Can you provide the distinct `activity_type_cd` values from your order catalog for labs and imaging?
- What percentage of imaging orders (CT, MRI) go through scheduling vs. walk-in?

### General:
- Are there any custom fields or workflows specific to your implementation we should be aware of?
- What date range and volume should we plan for in the extract?

## What We'll Deliver

Following our session, we'll finalize the CCL scripts tailored to your environment to extract:
- Specialist referrals with status tracking
- Lab and imaging orders (future orders) with scheduling information where applicable

Please let us know your availability for a 60-90 minute working session. We're happy to accommodate your schedule.

Thank you for your partnership on this.

Best regards,

[Your Name]

---

## Attachments to Include (Optional)

- Current draft CCL scripts for their review
- Summary document of the two workflows
