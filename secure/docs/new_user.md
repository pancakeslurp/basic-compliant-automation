# __create_user.sh__: Create a new user.

## Policy Considerations:
- __Least Privilege__: Admins should not be allowed to edit this script. If an admin can edit a script that runs as root, they can take over the root account.
- __Passwords__: Don't use a convention for the temporary password. Additionally, policy should enforce strong passwords.

## Compliance

The account controls listed below are taken from NIST SP 800-53 and NIST SP 800-171 and correspond to tasks in this script. SP 800-171 Rev 2 numbering is listed because the requirements are commonly used in defense contract requirements.

| Script feature or gap | SP 800-53 Rev 5 | SP 800-171 Rev 2 |
|---|---|---|
| Account creation as a managed, authorized process | AC-2 (account management) | 3.1.1, 3.5.1 |
| Temporary password with forced change (`chage -d 0`) | IA-5 (change default authenticators before first use) | 3.5.9 (temporary password, immediate change) |
| Random, unique per-account password | IA-5, IA-5(1) | 3.5.9 |
| Password never on the command line (`chpasswd` via stdin) | IA-5(6), IA-5(1) | 3.5.10, 3.5.11 |
| Username and argument validation, reserved names | SI-10 (input validation) | 3.1.2 |
| Fixed group, no privileged groups granted | AC-6 (least privilege) | 3.1.5 |
| Running as root only through a controlled path | AC-6, AC-6(9) | 3.1.5, 3.1.7 |
| Fail-secure lock if password setup fails | AC-2, IA-5 | 3.1.1 |
| Clear errors without leaking sensitive details | SI-11 | none directly |
| Audit logging of creation (who, what, when, outcome) | AU-2, AU-3, AU-12, AC-2(4) | 3.3.1, 3.3.2 |
| Protecting the log file (root-owned, mode 640) | AU-9 | 3.3.8, 3.3.9 |
| Accurate timestamps (UTC, synced clock) | AU-8 | 3.3.7 |
| Ticket or approval ID for each change | CM-3, AC-2 | 3.4.3 |
| Protecting the script itself (root-owned, not world-writable) | CM-5, SI-7 | 3.4.5 |
| Not reusing a previously issued username or UID | IA-4 | 3.5.5 |
| Secure delivery of the temporary credential | SC-8, IA-5(1) | 3.13.8 |
| Cryptographic randomness (FIPS-mode OpenSSL if CUI is involved) | SC-13 | 3.13.11 |

## Assumptions: Policy Controls

The script cannot enforce these on its own. They are assumed to be configured at the system or organizational level:

- **Password strength and reuse** (`pam_pwquality`, `pam_pwhistory`): SP 800-171 3.5.7 and 3.5.8; SP 800-53 IA-5(1)
- **Lockout after failed logons** (`pam_faillock`): SP 800-53 AC-7
- **Time synchronization** (chrony or NTP): SP 800-53 AU-8; SP 800-171 3.3.7
- **Log forwarding, retention, and failure alerts**: SP 800-53 AU-4, AU-5, AU-11; SP 800-171 3.3.4
- **Inactive account disabling**: SP 800-53 AC-2(3); SP 800-171 3.5.6
- **Multi-factor authentication for privileged access**: SP 800-53 IA-2; SP 800-171 3.5.3