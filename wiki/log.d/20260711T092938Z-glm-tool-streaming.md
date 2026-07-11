# Stream GLM tool arguments in Pi benchmark cells

- Added a Pi request extension that enables `tool_stream` for the pinned
  `z-ai/glm-5.2` candidate.
- Mounted and activated the extension in every Pi runner cell.
- This prevents large `write(plan.md)` calls from going silent until
  OpenRouter terminates them for upstream idleness, while preserving the
  benchmark's model, prompt, tools, and output.
