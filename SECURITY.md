# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| Latest release | Yes |
| Older releases | No — always upgrade to the latest version |

## Reporting a vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Report vulnerabilities privately via [GitHub Security Advisories](../../security/advisories/new).
You can also reach the maintainers at **security@glueckkanja.com**.

Include as much detail as possible:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We aim to acknowledge reports within **5 business days** and to provide a fix or mitigation within **30 days** for confirmed vulnerabilities.

## Scope

This module creates Azure Monitor resources (metric alerts, log query alerts, action groups). Security concerns in scope include:

- Overly permissive IAM or role assignments created by the module
- Managed identity privilege escalation paths
- Insecure defaults in alert configurations
- Sensitive values (tokens, keys) exposed through outputs
