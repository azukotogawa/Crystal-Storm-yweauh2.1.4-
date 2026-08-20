# Crystal Storm Studio

This directory is the maintained studio reference for Crystalstorm. It is written for designers, engineers, and future AI contributors. It describes the repository as it exists, separating implemented systems from intended direction.

Start here:

- [Identity](design/IDENTITY.md) and [Vision](design/VISION.md) define the product intent.
- [Gameplay](design/GAMEPLAY.md) records the playable loop and current prototype scope.
- [Technical architecture](engineering/TECHNICAL.md) explains the Godot runtime.
- [AI development guide](engineering/AI_DEVELOPMENT.md) defines safe contribution practice.
- [Project knowledge](management/PROJECT_KNOWLEDGE.md), [Backlog](management/BACKLOG.md), and [Decisions](management/DECISIONS.md) provide operational context.

Repository documents remain authoritative for their own concerns: `AGENTS.md` for coding rules, `manual_verification.md` for human sign-off, `STABILIZATION.md` for the current stabilization board, and `scripts/run_all_verify.sh` for the exact automated suite.

## Status language

**Implemented** means code and a production-scene path exist. **Verified** means an automated probe covers a behavior; it is not a claim of human visual or play-feel approval. **Planned** denotes design intent, not shipped behavior.

Do not treat old prose in the root `README.md` as a complete implementation inventory; it predates several now-present systems. Prefer code, scenes, configuration, and verification scripts when they disagree.
