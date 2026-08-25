# Deterministic Pi benchmark version preflight

**Problem:** With all benchmark cells running concurrently, the full Node-based
`pi --version` process could be CPU/I/O-starved past Hive's 120-second bounded
probe even though the installed Pi CLI and OpenRouter route were healthy. This
failed generation before any 0x Alpha provider request began.

**Action:** Pi benchmark containers now route `HIVE_PI_BIN` through a small
launcher. The required version probe reads the installed pinned npm package
metadata directly; every real Pi invocation delegates unchanged to the image's
`/usr/local/bin/pi`.

**Evidence:** `test/pi_bench_launcher_test.rb` pins both the metadata-only
version path and argument-preserving delegation. `test/hive_driver_test.rb`
pins the Pi-only read-only mount and environment binding.
