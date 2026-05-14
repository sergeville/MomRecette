# Story 49-9 - Document SharedSync physical validation gate

## Status

- done

## Context

The remaining `Minutes Inbox` sync-closure items on `upgrade/1.0.5` are no longer primarily app-code gaps.

What is still open is a mixed operator path:

- physical iPhone reverse-sync verification from recipe detail > `Sync`
- Apple provisioning/profile alignment for the new iCloud and ubiquity entitlements
- one final real-device Sprint 49 smoke pass
- the final merge-readiness decision for `upgrade/1.0.5`
- the later paid-services CloudKit follow-up

Those steps were already scattered across minutes, scripts, and migration notes, but there was no single repo-local artifact that separated:

- what is already observed in code
- what an agent can still do from this environment
- what the operator must validate manually on real hardware

## Story Goal

Create one canonical repo-local runbook that makes the blocked SharedSync closure steps explicit, evidence-driven, and auditable.

## Scope

In scope:

- add a runbook for the remaining physical-device SharedSync gate
- capture the current observed state from repo surfaces
- document the exact manual provisioning and smoke prerequisites
- document the merge gate for `upgrade/1.0.5`
- link the runbook from the current README/docs surfaces

Out of scope:

- pretending that physical-device validation already happened
- changing provisioning in Apple services from this repo
- enabling true CloudKit live sync before paid Apple services are available

## Acceptance Criteria

1. A repo-local runbook explains which requested tasks are agent-executable versus operator-blocked.
2. The runbook documents how to verify reverse sync from recipe detail > `Sync` on a physical iPhone.
3. The runbook documents the provisioning prerequisites for the new iCloud/ubiquity entitlement set.
4. The runbook documents the Sprint 49 real-device smoke flow and the merge/readiness decision gate.
5. The current README/docs surfaces link to the runbook so the next operator does not have to reconstruct the workflow from minutes.

## Traceability Notes

- Repo currently has no local `sprint-status.yaml` surface to update.
- This story restores the minimum BMAD artifact needed for a documentation-only slice without inventing a new local sprint-status system.
