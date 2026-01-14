# Cerner artifacts

This folder contains Cerner-related artifacts for the referral intelligence extract.

- `ccl/abax_kaleida_poc_referral_extract_core.prg`: minimal script for DVDev debugging (fewest dependencies)
- `ccl/abax_kaleida_poc_referral_extract_full.prg`: full extract with corrected encounter join semantics

If a client environment throws a “perform error”, start with the **core** program and incrementally add join blocks from the full script to identify the missing/unsupported table or column.
