# CLAUDE.md

This project keeps its canonical, continuously-updated agent context in **[AGENTS.md](AGENTS.md)** (repo root). Read it **fully** before starting any work, and follow its update protocol at the end of every session (§6–§9 must reflect what you did).

Verification gate before calling any change done (see AGENTS.md §5):

```bash
cd rust && cargo test
cd rust && cargo clippy --all-targets -- -D warnings
flutter analyze lib test
flutter test
```
