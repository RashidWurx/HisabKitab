---
description: Save progress - update docs, run checks, commit
---

Checkpoint the project:

1. Run `flutter analyze` and `flutter test`. Report any failures and fix them if they are simple.
2. Update `docs/PROJECT_STATE.md` (current phase, what is done, what is next, open items), `docs/FEATURE_MAP.md` (status and code map) and `docs/DECISIONS.md` (any new decisions and why).
3. Run `git status`, stage the relevant files (never secrets, `build/` or `.dart_tool/`), and commit with a clear message.
4. Reply with a short summary: what was saved, check results, and the commit message.

Extra notes from the user (optional): $ARGUMENTS
