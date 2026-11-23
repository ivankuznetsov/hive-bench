# Validate direct wrapper credentials (U2)

The wrapper accepts one supported API variable name, or an explicitly empty
allowlist with one regular OAuth source. Conflicting/incomplete declarations
refuse before Docker with fixed diagnostics; gate remains credential-free.
Ruby exceptions no longer embed potentially secret-bearing container stderr.
Focused decoy tests cover argv boundaries, absent keys, OAuth exclusivity,
sequential profiles and wrapper/Docker refusal classifications.
