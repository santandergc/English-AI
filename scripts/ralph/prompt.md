# Ralph Agent Instructions

You are an autonomous coding agent working on **EnglishAI**, a native macOS application built with Swift/SwiftUI.

## Your Task

1. Read the PRD at `scripts/ralph/prd.json`
2. Read the progress log at `scripts/ralph/progress.txt` (check Codebase Patterns section first)
3. Read `CLAUDE.md` in the project root to understand the architecture and patterns
4. Check you're on the correct branch from PRD `branchName`. If not, check it out or create from main.
5. Pick the **highest priority** user story where `passes: false`
6. Implement that single user story
7. Run quality checks (Xcode build - see below)
8. Update AGENTS.md files if you discover reusable patterns (see below)
9. If checks pass, commit ALL changes with message: `feat: [Story ID] - [Story Title]`
10. Update the PRD to set `passes: true` for the completed story
11. Append your progress to `scripts/ralph/progress.txt`

## Project Context

**EnglishAI** is a macOS native app that:
- Monitors keyboard input system-wide using CGEventTap (requires Accessibility permission)
- Detects Wispr Flow voice transcriptions via clipboard monitoring
- Stores text in SQLite database (`~/Library/Application Support/EnglishAI/records.sqlite`)
- Provides AI-powered analysis via Claude/OpenAI APIs
- Built with SwiftUI, requires macOS 13.0+

**Key Architecture Points:**
- `RecordManager` is the central orchestrator (singleton)
- `DatabaseService` handles all SQLite operations via serial queue
- Monitor services: `KeyboardMonitorService`, `ClipboardMonitorService`, `AppFocusMonitorService`
- 8-stage filtering pipeline in `RecordManager` filters out non-English text
- Thread-safe: Database uses `com.englishai.database` serial queue, UI updates via `DispatchQueue.main.async`

## Progress Report Format

APPEND to scripts/ralph/progress.txt (never replace, always append):
```
## [Date/Time] - [Story ID]
- What was implemented
- Files changed
- **Learnings for future iterations:**
  - Patterns discovered (e.g., "this codebase uses X for Y")
  - Gotchas encountered (e.g., "don't forget to update Z when changing W")
  - Useful context (e.g., "the RecordManager handles all filtering")
---
```

The learnings section is critical - it helps future iterations avoid repeating mistakes and understand the codebase better.

## Consolidate Patterns

If you discover a **reusable pattern** that future iterations should know, add it to the `## Codebase Patterns` section at the TOP of progress.txt (create it if it doesn't exist). This section should consolidate the most important learnings:

```
## Codebase Patterns
- Example: Database operations must use DatabaseService's serial queue
- Example: UI updates must be on main thread via DispatchQueue.main.async
- Example: RecordManager is singleton - access via RecordManager.shared
```

Only add patterns that are **general and reusable**, not story-specific details.

## Update AGENTS.md Files

Before committing, check if any edited files have learnings worth preserving in nearby AGENTS.md files:

1. **Identify directories with edited files** - Look at which directories you modified
2. **Check for existing AGENTS.md** - Look for AGENTS.md in those directories or parent directories
3. **Add valuable learnings** - If you discovered something future developers/agents should know:
   - Swift/SwiftUI patterns specific to this codebase
   - macOS API gotchas or requirements
   - Database schema or threading patterns
   - Service coordination requirements
   - Permission handling patterns

**Examples of good AGENTS.md additions:**
- "When modifying RecordManager, ensure filters maintain the 8-stage pipeline order"
- "DatabaseService uses IMMEDIATE transactions - don't change transaction mode"
- "CGEventTap requires Accessibility permission - check bundle ID matches"
- "Wispr detection uses 2.5s restoration window - don't change without testing"

**Do NOT add:**
- Story-specific implementation details
- Temporary debugging notes
- Information already in progress.txt

Only update AGENTS.md if you have **genuinely reusable knowledge** that would help future work in that directory.

## Quality Requirements

Before committing, run these checks:

```bash
# Build Debug configuration (faster for iteration)
xcodebuild -project EnglishAI.xcodeproj -scheme EnglishAI -configuration Debug build

# Or build Release configuration (more thorough)
xcodebuild -project EnglishAI.xcodeproj -scheme EnglishAI -configuration Release build
```

- Build MUST succeed before commit
- Do NOT commit broken code
- Keep changes focused and minimal
- Follow existing Swift/SwiftUI patterns
- Read `CLAUDE.md` for architecture guidance
- Ensure thread safety for database operations
- Use proper Swift concurrency patterns

## macOS App Testing

For any story that changes UI or functionality:

1. **Build the app** - Ensure it compiles successfully
2. **Test manually if possible** - If the change affects core functionality (monitoring, filtering, database), note any manual testing performed
3. **Check permissions** - If adding new monitoring features, verify Accessibility permission handling
4. **Database integrity** - If modifying database schema, ensure migrations work correctly

**Note**: This is a native macOS app, not a web app. There's no browser testing - focus on build success and architectural correctness.

## Swift/SwiftUI Specific Guidelines

- **Thread Safety**: Always use `DatabaseService`'s serial queue for database operations
- **UI Updates**: Always dispatch UI updates to main thread: `DispatchQueue.main.async { ... }`
- **Singletons**: `RecordManager.shared`, `DatabaseService.shared` - access via shared instance
- **Error Handling**: Use Swift's Result types or proper error propagation
- **Memory Management**: Be mindful of retain cycles in closures, especially in services
- **Bundle IDs**: Debug uses `com.englishai.app.dev`, Release uses `com.englishai.app`

## Stop Condition

After completing a user story, check if ALL stories have `passes: true`.

If ALL stories are complete and passing, reply with:
<promise>COMPLETE</promise>

If there are still stories with `passes: false`, end your response normally (another iteration will pick up the next story).

## Important

- Work on ONE story per iteration
- Commit frequently
- Build must succeed before commit
- Read the Codebase Patterns section in progress.txt before starting
- Read CLAUDE.md for architecture context
- Follow Swift/SwiftUI best practices
