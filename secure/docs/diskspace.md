# Requirement F: Check and clean up disk space.

## Purpose

This script serves to check available disk space and clear space by deleting directories set by a variable.

## Compliance Considerations

The following controls are implemented in this script:

| Control Name | Control Designator (NIST SP 800-53) | 800-171 Ref |
|---|---|---|
| Access Enforcement / Least Privilege | AC-6 | 3.1.5 |
| Auditing Privileged Functions | AC-6(9) | 3.1.7 |
| Event Logging / Content of Audit Records | AU-2 / AU-3 | 3.3.1, 3.3.2 |
| Audit Log Storage Capacity | AU-4 | n/a |
| Response to Audit Logging Process Failures | AU-5 | 3.3.4 |
| Time Stamps | AU-8 | 3.3.7 |
| Protection of Audit Information | AU-9 | 3.3.8, 3.3.9 |
| Audit Record Generation | AU-12 | 3.3.1 |
| Configuration Change Control | CM-3 | 3.4.3 |
| Impact Analyses | CM-4 | 3.4.4 |
| Access Restrictions for Change | CM-5 | 3.4.5 |
| Media Sanitization (unlink only; see note) | MP-6 | 3.8.3 |
| Information in Shared System Resources | SC-4 | 3.13.4 |
| Software, Firmware, and Information Integrity | SI-7 | n/a |
| Information Input Validation | SI-10 | n/a |
| Error Handling | SI-11 | n/a |

**Note:** `rm` only unlinks files. It does not sanitize the underlying media (SSD wear leveling and TRIM can leave data recoverable), so MP-6 is only partly met. Media containing regulated data needs a sanitization method from NIST SP 800-88.
