# Preserve Codex judge limit markers

Codex judge failures now inspect the complete CLI stderr stream before
truncating its diagnostic. A usage wall is promoted to a leading
`limits_reached` marker so the benchmark workflow can distinguish a temporary
provider limit from a real judge failure and let the Hive daemon retry the lane.

A regression covers the live failure shape where the usage message follows a
long Codex banner.
