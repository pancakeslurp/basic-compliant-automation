# Requirement E: Network Testing

This test suite consists of four scripts total:
* e_ping_google.sh - Pings google.com.
* e_ping_google_dns.sh - Pings Google's public DNS server (8.8.8.8).
* e_resolve_example_dns.sh - Resolves the DNS entry for example.com.
* menu.sh: Provides the user with a menu to seamlessly run each script.

## Compliance Considerations

The following controls are implemented across the four scripts used in this task:

| Control Name | Control Designator (NIST SP 800-53) | 800-171 Ref | Script |
|---|---|---|---|
| Least Privilege | AC-6 | 3.1.5 | __All__ |
| Event Logging / Content of Audit Records | AU-2 / AU-3 | 3.3.1 | __All__ |
| Time Stamps | AU-8 | 3.3.7 | __All__ |
| Audit Record Generation | AU-12 | 3.3.1 | __All__ |
| Access Restrictions for Change | CM-5 | 3.4.5 | __All__ |
| Least Functionality | CM-7 | 3.4.6 | __e_ping_google_dns.sh__ |
| Boundary Protection | SC-7 | 3.13.1 | __e_ping_google_dns.sh__ |
| Secure Name/Address Resolution Service | SC-20 / SC-21 / SC-22 | n/a | __e_resolve_example_dns.sh__ |
| System Monitoring | SI-4 | 3.14.6 | __e_ping_google.sh__, __e_ping_google_dns.sh__, __e_resolve_example_dns.sh__ |
| Software, Firmware, and Information Integrity | SI-7 | n/a | __All__ |
| Information Input Validation | SI-10 | n/a | __e_resolve_example_dns.sh__, __e_menu.sh__ |
| Error Handling | SI-11 | n/a | __All__ |

# Requirement E1: Flowchart Diagram

```mermaid
flowchart TD
    title["Network Test Workflow"]
    Start([Start]) --> Menu{Main Menu}

    Menu -->|Option 1| A[Run e_ping_google.sh]
    Menu -->|Option 2| B[Run e_ping_google_dns.sh]
    Menu -->|Option 3| C[Run e_resolve_example_dns.sh]

    subgraph A_Script [e_ping_google.sh]
        A --> A1[Set variables]
        A1 --> A2{Running as root?}
        A2 --> |Yes| A3[Exit with error]
        A2 --> |No| A4{File permissions check}
        A4 --> |Pass| A5{Ping google.com}
        A4 --> |Fail| A3
        A5 --> |Success| A6{Message: #quot;Network is up.#quot;}
        A5 --> |Fail| A7{Message: #quot;No connection.#quot;}
        A6 --> A8[Return to main menu]
        A7 --> A8
    end

    subgraph B_Script [e_ping_google_dns.sh]
        B --> B1[Set variables]
        B1 --> B2{Running as root?}
        B2 --> |Yes| B3[Exit with error]
        B2 --> |No| B4{File permissions check}
        B4 --> |Pass| B5{Ping 8.8.8.8}
        B4 --> |Fail| B3
        B5 --> |Success| B6{Message: #quot;Network is up.#quot;}
        B5 --> |Fail| B7{Message: #quot;No connection.#quot;}
        B6 --> B8[Return to main menu]
        B7 --> B8
    end

    subgraph C_Script [e_resolve_example_dns.sh]
        C --> C1[Set variables]
        C1 --> C2{Running as root?}
        C2 --> |Yes| C3[Exit with error]
        C2 --> |No| C4{File permissions check}
        C4 --> |Pass| C5[Configure DNS resolver]
        C4 --> |Fail| C3
        C5 --> C6[nslookup example.com]
        C6 --> C7[Reformat nslookup output]
        C7 --> C8{Validate nslookup info}
        C8 --> |Success| C9[Display success message with IP]
        C8 --> |Failure| C10[Display failure message]
        C9 --> C11[Return to main menu]
        C10 --> C11
    end

    A3 --> Menu
    B3 --> Menu
    C3 --> Menu
    A8 --> Menu
    B8 --> Menu
    C11 --> Menu
```
