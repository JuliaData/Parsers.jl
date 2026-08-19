# Security policy

Parsers processes untrusted text and byte buffers. Please report a possible
memory-safety, bounds, denial-of-service, or input-validation vulnerability
privately.

## Report a vulnerability

Use **Report a vulnerability** on the repository's GitHub **Security** tab.
Do not open a public issue for an unpatched vulnerability. If private
vulnerability reporting is not available, contact a JuliaData maintainer
privately before sharing the reproducer or affected input.

Include the affected Parsers and Julia versions, platform and word size, the
smallest reproducer, expected impact, and any known workaround. Do not include
secrets or unrelated user data.

The maintainers will confirm receipt, investigate the report, and coordinate
disclosure after a fix is available. Response time depends on maintainer
availability.

## Supported versions

The latest registered Parsers release receives security fixes. Older releases
can receive a fix when the maintainers judge a backport to be practical and
necessary.
