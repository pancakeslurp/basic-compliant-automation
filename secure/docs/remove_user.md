## B. __delete_user.sh__: Delete a user.

## Policy Considerations

- __Irreversibility and Confirmation__: Consider a confirmation prompt that requires a fully-typed answer rather than simply y/n.
- __Data Retention__: Immediate deletion could violate retention minimum requirements for regulated data (CUI, PHI, etc.), so the organization should define whether they will archive the home and mail spool directories. If so, the archives should be stored on a different machine and encrypted at rest.
- __Data Disposal/Sanitization__: The commands `rm` and `shred` are ineffective on SSDs due to wear leveling and TRIM. The organization should implement disk-level encryption and cryptographic erase, or a physical media destruction policy.
- __Orphaned Artifacts__: The `userdel -r` command unlinks files but does not erase them effectively. Identify files owned by the UID flagged for deletion that exist outside the home and mail spool directories. This includes running processes, sudoers entries, SSH keys, cron jobs and group memberships, among other things.
- __Audit Logging__: Log who ran the script, when (verifying the log timestamps), the target, ticket ID, and the outcome. Failed commands should also be logged. Log files should be restricted to append-only so they can not be deleted or overwritten.
- __Error Handling__: Fail closed on errors, use meaningful exit codes, and verify results instead of trusting the `userdel` exit status. Do not print senitive information in error messages.
- __Scheduling__: If the script is run automatically on a schedule (e.g. a cron job), failed tasks should be logged and exit cleanly but should not terminate the batch.
- __Industry Requirements__: Know and maintain compliance with industry data retention, access and logging requirements:
    - CUI: Protect CUI during offboarding and sanitize media containing CUI.
    - HIPAA: Termination procedures and six-year data retention requirement.
    - PCI DSS: Immediately revoke offboarded users' access and keep audit logs.

## Compliance Control Mapping

The account controls below are listed in NIST SP 800-53 and NIST SP 800-171 Rev. 5 and correspond to tasks in this script. SP 800-171 Rev 2 numbering is listed because the requirements are commonly used in defense contract requirements.

| Control Name | Control Designator (NIST SP 800-53) | 800-171 Ref |
|---|---|---|
| Account Management | AC-2 | 3.1.1 |
| Automated Audit Actions | AC-2(4) | 3.1.1 |
| Access Enforcement / Least Privilege | AC-3 / AC-6 | 3.1.2, 3.1.5 |
| Event Logging / Content of Audit Records | AU-2 / AU-3 | 3.3.1 |
| Time Stamps | AU-8 | 3.3.7 |
| Protection of Audit Information | AU-9 | 3.3.8 |
| Audit Record Generation | AU-12 | 3.3.1 |
| Configuration Change Control | CM-3 | 3.4.3 |
| Access Restrictions for Change | CM-5 | 3.4.5 |
| Identifier Management | IA-4 | 3.5.5 |
| Media Sanitization | MP-6 | 3.8.3 |
| Protection of Information at Rest | SC-28 | 3.13.16 |
| Information Input Validation | SI-10 | n/a |
| Error Handling | SI-11 | n/a |
| Information Management and Retention | SI-12 | n/a |
| Personnel Termination | PS-4 | 3.9.2 |
