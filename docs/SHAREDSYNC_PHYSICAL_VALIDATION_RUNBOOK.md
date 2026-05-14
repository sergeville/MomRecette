# SharedSync physical validation runbook

## Purpose

This runbook closes the remaining sync-closure ambiguity on `upgrade/1.0.5` without overstating validation.

It exists to answer one practical question:

What can be advanced from the repo today, and what still requires a human operator with Apple access and physical devices?

## Current observed state

Observed from the repo:

- `Views/Detail/RecipeDetailView.swift` still exposes `Sync` from the recipe-detail toolbar menu.
- `Views/Components/ImportView.swift` still contains both:
  - the manual package import/export path
  - the `SharedSync` queue/bootstrap path
- `MomRecette.entitlements` already declares:
  - `iCloud.com.villeneuves.MomRecette`
  - `CloudDocuments`
  - `CloudKit`
  - the ubiquity container identifiers
- `scripts/package_sergeiphone_ipa.sh` can archive/export an iPhone build, but it cannot guarantee that the active provisioning profile already contains the required entitlements or the connected test device.
- `docs/CLOUDKIT_SYNC_MIGRATION.md` remains the future architecture target, not the current release gate for this branch.

Validated in prior repo evidence:

- Mac plus simulator coverage already exists for the queue-based `SharedSync` path.
- No repo evidence currently proves a completed real-device pass across the remaining iPhone/iPad hardware gate.

## Executability split

Agent-executable from this environment:

- inspect the current code path and entitlements
- document the exact operator checklist
- keep the branch/PR trace clean

Operator-only or Apple-account-blocked:

- update the iOS provisioning profile
- add the connected physical iPhone to the profile/device set
- install a signed build on the real iPhone
- run reverse-sync manually from recipe detail > `Sync`
- rerun the real-device Sprint 49 smoke pass
- make the final merge decision after the hardware pass

Future-only, not part of the current release gate:

- true CloudKit live sync across Mac/iPhone/iPad after paid Apple services are available

## Task-by-task status

### 1. Verify reverse sync again on iPhone using recipe detail > `Sync`

Status: blocked on signed physical-device install and manual operator action.

What is already true in code:

- the recipe-detail overflow menu still exposes `Sync`
- opening it presents the shared `ImportView` sheet

Manual validation steps:

1. Install a freshly signed build on the physical iPhone.
2. Open any recipe detail screen.
3. Tap the overflow menu, then tap `Sync`.
4. Use the intended reverse-sync path:
   - `Importer un package MomRecette` for an explicit package handoff, or
   - the primary `SharedSync` action if the device already has the remembered queue and a resolved checkpoint
5. Confirm the destination data changes on iPhone as expected.
6. Capture evidence:
   - which source artifact was used
   - the visible result banner/message
   - whether the expected recipes/grocery list/photos changed
   - for package import, the backup path shown by the app before replacement

Pass condition:

- the physical iPhone can start the flow from recipe detail > `Sync`
- the selected sync mechanism completes without a signing/runtime blocker
- the imported or synchronized data is visible afterward

### 2. Decide whether to merge `upgrade/1.0.5` after one final smoke pass across Mac/iPhone/iPad

Status: not ready to decide yet from this environment alone.

Current working decision:

- keep `upgrade/1.0.5` as review-ready from a code/docs perspective
- do not call it hardware-validated or merge-ready until the physical pass below succeeds

Required gate before merge:

- Mac smoke still clean
- physical iPhone smoke passes
- physical iPad smoke passes, or the operator records why Mac + iPhone + second real device is the accepted replacement gate
- the reverse-sync entry flow above succeeds on the real iPhone
- Sprint 49 real-device `SharedSync` smoke passes

If any hardware gate fails:

- do not merge as release-ready
- keep the queue-based path as the active hardening direction

### 3. If paid Apple services become available later, continue from the Core Data foundation and enable CloudKit properly

Status: future follow-up, not current branch closure.

Use `docs/CLOUDKIT_SYNC_MIGRATION.md` as the architecture contract for that later phase.

Do not conflate this future work with the current queue-based `SharedSync` release gate.

The later CloudKit gate should start only after:

- Apple services are actually available
- provisioning and container access are stable
- the current queue-based branch is either shipped or intentionally superseded

### 4. Update the Apple provisioning profile for the new iCloud/ubiquity entitlements and the connected physical iPhone

Status: blocked on Apple Developer/Xcode operator access.

Manual checklist:

1. Open the signing target for `com.villeneuves.MomRecette`.
2. Regenerate or refresh the iOS provisioning profile so it matches the current entitlements in `MomRecette.entitlements`.
3. Confirm the profile includes:
   - `iCloud.com.villeneuves.MomRecette`
   - `CloudDocuments`
   - `CloudKit`
   - the ubiquity container identifiers
4. Add the currently connected physical iPhone device to the allowed device list.
5. Refresh profiles locally in Xcode before attempting device install/export again.

Important note:

- the entitlements are already declared in the repo
- the remaining risk is profile/device alignment, not a missing entitlement declaration in source

### 5. Rerun Sprint 49 physical-device smoke validation

Status: manual real-device gate.

Recommended operator flow:

1. Choose the source device that already contains the trusted local library.
2. Use the canonical iCloud `SharedSync` location, not the simulator override path.
3. Publish or confirm the latest shared backup from the source device.
4. On one fresh target device, bootstrap from the latest shared backup.
5. Confirm the target device converges to the expected recipe state.
6. Create a new change on the source device.
7. Bring the target app to foreground after the throttle window and confirm the queue pulls the new change.
8. Repeat with at least one additional real device.
9. Run the final branch smoke across:
   - Mac
   - iPhone
   - iPad

Evidence to capture:

- which device acted as the source
- which device was the fresh bootstrap target
- whether `MomRecette-Latest-Backup.json` existed in the canonical shared location
- whether launch/foreground sync converged on the target
- any visible sync result summaries shown by the app
- whether a retry was needed because of signing, iCloud, or runtime issues

### 6. After the physical pass, confirm whether the queue-based path is the release-candidate sync workflow

Status: provisional answer already exists, final answer still blocked on task 5.

Current answer before the physical pass:

- keep the queue-based `SharedSync` path as the active sync direction
- do not call it fully release-candidate ready across all devices yet

Final answer after the physical pass:

- if the real-device smoke succeeds and the Mac/iPhone/iPad gate is clean, treat the queue-based path as the release-candidate sync workflow for this branch
- otherwise keep it as the correct workflow to continue hardening, but not yet the release-candidate signoff path

## Recommended evidence record

When the operator runs the blocked steps, capture the outcome using these labels:

- `Observed`: seen in code, config, or UI, but not yet proven end-to-end on hardware
- `Validated`: completed end-to-end with captured evidence
- `Blocked`: could not proceed because of provisioning, account access, or device availability
- `Decided`: explicit merge/readiness decision made from the available evidence

Minimal write-back template:

- Task:
- Label:
- Device(s):
- Source artifact or shared path:
- Result:
- Evidence captured:
- Next action:

## Merge recommendation right now

Current recommendation from repo evidence alone:

- do not merge `upgrade/1.0.5` as hardware-validated yet
- proceed only after the provisioning update and one clean real-device SharedSync smoke pass
