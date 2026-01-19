# Ralph - Autonomous Development Loop

## What is Ralph?

Ralph runs Claude Code in a loop until all PRD tasks are complete. Each iteration is a fresh context - memory persists only via files.

## Quick Start

```bash
# 1. Create PRD in tasks/prd-[feature].md
# 2. Convert to scripts/ralph/prd.json
# 3. Run:
./scripts/ralph/ralph.sh [max_iterations]
```

## Files

| File | Purpose |
|------|---------|
| `ralph.sh` | The bash loop |
| `prompt.md` | Instructions per iteration |
| `prd.json` | Current feature tasks |
| `progress.txt` | Learnings between iterations |
| `archive/` | Completed features |

## Memory Between Iterations

Each iteration has NO memory except:
- `prd.json` - which stories are done
- `progress.txt` - what was learned
- `git history` - code changes
- `AI-CODE.md` files - codebase patterns

## Patterns

- One feature at a time (auto-archives on branch change)
- Stories must be small (fit in one context window)
- End-to-end stories (not layer-by-layer)
- All quality checks must pass before commit
- UI stories require browser verification
