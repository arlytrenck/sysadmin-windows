# Recovery access and directory services runbook

This runbook covers a disciplined response when normal Windows Server or Active Directory administration is unavailable. Use it alongside the incident-response and backup/DR runbooks; it is not a substitute for tested system-state backups.

## First rule: identify the scope

Determine whether the issue affects one workstation, one server, one domain controller, a site, or the whole directory. Check DNS resolution, time synchronization, network reachability, and the current domain-controller role before resetting passwords or changing group membership. A time, DNS, or replication failure often presents as an authentication failure.

Record the time, caller, affected account or service, error text, and last known good change. Do not perform a broad password reset or force replication until you understand the blast radius.

## Break-glass prerequisites

Maintain and periodically test:

- Two protected emergency administrative accounts that are excluded from routine use and monitored for sign-in.
- Console or hypervisor access to every domain controller.
- A current system-state backup and documented authoritative/non-authoritative restore decision tree.
- A secure copy of recovery keys, local administrator access, and the service-account inventory.
- Out-of-band contact and escalation details.

Emergency accounts must have long unique credentials, MFA where supported, limited delegation, and an explicit owner. Any use should create an investigation item and trigger credential rotation afterward.

## Access recovery flow

1. Confirm the target machine and current time source. Kerberos is sensitive to clock skew; correct time before changing identities.
2. Verify DNS using the intended internal resolver. Do not point a domain member at a public resolver as a permanent workaround.
3. Use a console or approved local administrator path to inspect networking, Event Viewer, and service state.
4. If a user cannot sign in, inspect account status, group policy result, and domain-controller availability before unlocking or resetting the account.
5. If an administrator cannot elevate, validate membership and UAC policy, then use a named emergency account only for the minimum repair.
6. Test with a new session from a known-good client. Keep the console open until ordinary access is confirmed.
7. Remove temporary local-admin memberships, firewall exceptions, and remote-access changes.

## Active Directory safeguards

- Never restore a domain controller from a VM checkpoint as a routine rollback method. Use supported system-state recovery procedures.
- Do not seize FSMO roles unless the original holder is permanently unavailable and the decision is documented.
- Before changes to privileged groups or GPOs, export the current state and record the intended rollback.
- Treat DNS zones, SYSVOL, and time service as first-class AD dependencies. Verify their health before treating replication errors in isolation.
- Use least privilege for service accounts; avoid granting Domain Admin simply to resolve an application issue.

## Post-recovery verification

Verify authentication for a standard user, a privileged user, and a service account where relevant. Check directory replication, DNS registration, time synchronization, event logs, and the health of dependent services. Confirm backups still run and that the recovery action did not disable monitoring or audit forwarding.

## Follow-up record

Document the symptom, scope, evidence, access method, command or console changes, validation, and cleanup. Rotate any emergency credential used. Turn recurring checks into monitoring: replication health, domain-controller backup age, privileged-group changes, and break-glass sign-ins should all be observable.
