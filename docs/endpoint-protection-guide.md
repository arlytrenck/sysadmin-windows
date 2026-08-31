# Endpoint Protection Guide

A baseline for keeping Windows Defender (or an equivalent product) doing
its job across a fleet, rather than silently drifting into a disabled or
stale state. Pairs with
[Defender-Status-Check.ps1](../scripts/Defender-Status-Check.ps1), which
checks a single host against several of the points below.

## Real-time protection

- **Real-time protection should be on everywhere it isn't explicitly
  replaced by another product.** If a third-party AV/EDR product is the
  intended standard, verify it's actually installed and reporting
  healthy on every host — Defender disabling itself in favor of a
  product that then fails to start silently is a real and easy-to-miss
  gap.
- **Don't leave real-time protection off after troubleshooting.** It's
  a common (and reasonable) step to temporarily disable it while
  diagnosing a performance issue or a false-positive block — the
  failure mode is forgetting to turn it back on. Track and re-check
  any host where it was intentionally disabled.

## Exclusions

- **Keep the exclusion list as short as possible, and documented.**
  Every path/process exclusion is a place malware can hide undetected
  if it lands there. A common source of scope creep: a vendor's install
  guide says "exclude this folder for performance," and the exclusion
  outlives the reason it was added.
- **Review exclusions periodically**, not just when adding a new one —
  an exclusion added for software that's since been removed should be
  removed with it.
- **Prefer narrow, specific exclusions** (a single file or process)
  over broad ones (an entire drive or user profile) wherever the
  vendor's guidance allows it.

## Signature and platform updates

- **Signatures should update at least daily** — `Defender-Status-Check.ps1`'s
  default 3-day threshold is a "something is broken" alarm, not a
  target; a healthy, connected host typically updates signatures
  multiple times a day.
- **A host with consistently stale signatures usually has a connectivity
  or WSUS/update-source problem**, not a Defender problem specifically —
  check whether the host can reach its update source at all before
  troubleshooting Defender itself.
- **Platform updates (the Defender engine itself, not just signatures)
  matter too** — they ship through Windows Update and carry detection
  and performance improvements independent of signature freshness.

## Scanning

- **Scheduled quick scans plus periodic full scans** is the standard
  baseline — real-time protection catches most things as they happen,
  but a scan catches anything that arrived before protection was
  enabled or through a path real-time monitoring doesn't cover.
- **A host with no scan history is a visibility gap**, not necessarily
  an active compromise — but it means you have no evidence either way,
  which is its own problem worth fixing.

## Alerting and response

- **Wire Defender detections into your monitoring/alerting stack**
  (see [monitoring-alerting-guide.md](monitoring-alerting-guide.md))
  rather than relying on someone noticing a balloon notification on a
  server that runs headless.
- **Treat a detection on a server differently from one on a workstation**
  — a server compromise usually has a larger blast radius (more
  connected systems, more privileged accounts nearby) and warrants a
  faster, more thorough response, including checking
  [incident-response-runbook.md](incident-response-runbook.md) rather
  than just clearing the alert.
- **A single detection that "looks handled" is still worth a quick
  root-cause pass** — how did the file get there in the first place is
  often more informative than the detection itself.
