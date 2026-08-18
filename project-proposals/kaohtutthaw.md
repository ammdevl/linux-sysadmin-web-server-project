# Mail Server — Linux SysAdmin
**Project Proposal**  
**Submitted by:** [kaohtutthaw]  
**Date of Submission:** 2026-08-18  
**Target Environment:** Ubuntu 24.04 LTS  

## Gist
A local Mail Server using Postfix and Dovecot, providing secure internal email communication, user mailbox management, and group-based access control for a school lab environment[cite: 1].

## Story
In a school computer lab, students and instructors need a private, secure, and offline-capable email system to practice network communication and submit assignments locally[cite: 1]. Without a dedicated mail server, users rely on external services or lack a proper identity on the local network[cite: 1]. A local Mail Server allows students to have unique accounts (User & Group Management) with restricted mailbox access (File & Directory Permissions), ensuring privacy and isolation within the lab.

## Why
* Provides an internal email infrastructure for students and staff using custom domain names (e.g., `student01@lab.local`).
* Implements system-level **User & Group Management** to isolate student, teacher, and admin accounts.
* Enforces strict **File & Directory Permissions** (Linux POSIX permissions) on mailboxes (`~/Maildir`) so users can only read their own emails.
* Eliminates dependency on public internet access for internal school messaging.

## Why Not
* **No External Email Delivery:** Cannot send/receive emails to/from external domains like Gmail or Yahoo[cite: 1].
* **No Webmail Interface:** Access is via CLI (`mailutils`) or standard IMAP/POP3 clients, not Roundcube/Webmail (kept simple for this phase)[cite: 1].
* **No SSL/TLS Encryption:** Uses plain text authentication over the isolated local network (production-grade SSL is out of scope)[cite: 1].
* **No Spam Filtering:** No SpamAssassin or ClamAV integration in this phase.

## Tech Spec
* **OS / Distro:** Ubuntu 24.04 LTS[cite: 1]
* **Core Services & Packages:**
  * `postfix` — Mail Transfer Agent (MTA) for routing and sending emails
  * `dovecot-imapd` / `dovecot-pop3d` — Mail Delivery Agent (MDA) for fetching emails
  * `mailutils` — Command-line utilities for sending/reading mail
  * `ufw` — Firewall configuration[cite: 1]
* **User, Group & Permission Control:**
  * **Groups:** `students`, `instructors`, `mailadmin`
  * **Permissions:** Maildirs set to `700` (`rwx------`), owned by individual users to prevent unauthorized access.
* **Architecture / Flow:**
  * Sender (`user1@lab.local`) → Postfix (SMTP Port 25) → Delivers to `/home/user2/Maildir`
  * Receiver (`user2`) → Dovecot (IMAP Port 143 / POP3 Port 110) → Reads Mailbox
  * Storage: Maildir format stored in each user's home directory.

## Security & Access Control Plan
* **Directory Permissions:** Mailbox directories (`~/Maildir`) are automatically created with `700` permissions (readable/writable only by the account owner).
* **Group Management:** Users are assigned to system groups (`students` / `instructors`) to control sudo privileges and access limits.
* **Firewall Rules:** UFW allows only SMTP (TCP 25), IMAP (TCP 143), and POP3 (TCP 110) within the local subnet[cite: 1].
* **Backup:** Configuration files (`/etc/postfix/`, `/etc/dovecot/`) backed up via script[cite: 1].

## Definition of Done
* Postfix and Dovecot services install and start successfully without errors[cite: 1].
* Users and groups (`students`, `instructors`) are created with appropriate permissions.
* User mailboxes are restricted to `700` permissions, preventing cross-user mail reading.
* `user1` can send an email to `user2` via the `mail` command or IMAP/POP3[cite: 1].
* Mail Server services survive a server reboot (`systemctl enable postfix dovecot`)[cite: 1].

## Key References & Documentation
* Ubuntu Server Mail Documentation[cite: 1]
* Postfix Basic Configuration Guide
* Dovecot Documentation (Maildir Setup)
* Linux File Permissions & Access Control Guide