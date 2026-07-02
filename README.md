# EnglishAI

EnglishAI is a macOS-native English improvement coach. It observes the English a user naturally writes and speaks across their day, analyzes the patterns, and turns those patterns into personalized practice.

The product is not just a grammar checker. The core promise is:

> EnglishAI should always know the user's highest-leverage 20% of English to practice so they can improve faster.

That 20/80 principle is the most important philosophy of the product. The app should understand how the user actually writes, talks, explains, asks, reacts, and works, then identify the smallest set of words, verbs, expressions, grammar patterns, and speaking habits that will create the biggest visible improvement.

## Product Philosophy

### Personalized Improvement, Not Generic English

Most English learning tools teach a curriculum. EnglishAI should teach the user's curriculum.

The product should answer these questions continuously:

- What does this user repeatedly try to express?
- What vocabulary would make their real communication richer?
- Which verbs, connectors, phrasal verbs, idioms, and sentence structures would unlock better expression for them?
- Which mistakes appear often enough to deserve practice?
- Which weaknesses are blocking fluency, confidence, or professional clarity?
- What is the next small practice set that will create the biggest improvement?

The AI coach should not treat every correction equally. A typo, a rare grammar edge case, and a recurring weak pattern do not have the same value. The system should rank improvement opportunities by leverage.

### The 20/80 English Coach

The app's highest-level intelligence should be a living model of the user's English.

For each user, EnglishAI should maintain a personalized map of:

- High-frequency mistakes
- Missing vocabulary that would enrich the user's natural topics
- Overused words and weak alternatives
- Underused verbs and expressions
- Grammar patterns that repeatedly reduce clarity
- Spoken-English habits from voice recordings and transcriptions
- Writing tone patterns across apps and contexts
- Weaknesses that are due for review
- Mastered areas that can be practiced less often

The coach should then produce direct guidance:

- "These are the 12 expressions that would immediately upgrade how you write at work."
- "You often use simple verbs like `make`, `do`, and `get`; this week, practice these stronger alternatives."
- "Your biggest speaking improvement is sentence structure under pressure, not vocabulary."
- "You keep making conditionals too long; practice shorter, cleaner versions."
- "This mistake appeared 7 times this week, so it is worth drilling today."

## Product Overview

EnglishAI currently works as a background macOS app that captures natural English input, stores it locally, analyzes it with AI, and provides practice experiences.

The product has four main loops:

1. **Capture**: Collect real English from keyboard input, Wispr Flow transcriptions, and microphone recordings.
2. **Analyze**: Use AI to identify grammar issues, phrasing improvements, vocabulary opportunities, positive patterns, and overall progress.
3. **Practice**: Generate targeted exercises based on the user's weaknesses.
4. **Remember**: Track progress and use spaced repetition so practice focuses on what matters now.

## Current Capabilities

### Real-World English Capture

EnglishAI records English from multiple sources:

- **Keyboard monitoring** using macOS Accessibility APIs.
- **Wispr Flow detection** through clipboard pattern monitoring.
- **Voice recording** through the Mac microphone, with transcription support through Whisper.
- **App context tracking** so records know where the English was produced.

The goal is to learn from the user's real communication, not from artificial placement tests.

### Intelligent Filtering

The app filters captured text before storing it. The filtering system removes low-value or non-language content such as single characters, numbers-only text, short fragments, terminal commands, and code-like strings.

This matters because the product only becomes intelligent if the learning data is clean enough to represent real English.

### AI Analysis

The analysis system supports Claude and OpenAI providers. It reviews captured records and completed voice transcriptions, then returns:

- Grammar corrections
- Phrasing improvements
- Vocabulary insights
- Positive feedback
- Overall score
- Summary of the user's English patterns

This is the foundation for the AI coach, but the product direction should push analysis beyond "what was wrong" into "what should this user practice next."

### Practice System

EnglishAI includes a practice area with AI-generated exercises. The exercise system is designed around multiple formats:

- Single choice
- Multiple choice
- Fill in the blank
- Free response
- Error correction
- Sentence reorder
- Matching
- Word formation

Exercises are generated from the user's weaknesses, can vary by difficulty, and are intended to support daily practice and on-demand practice.

### Progress and Spaced Repetition

The product includes weakness progress tracking concepts:

- Total attempts
- Correct attempts
- Accuracy
- Last practiced date
- Next review date
- Mastery level

This should become the memory layer of the product. The app should know what the user is improving, what is still weak, and what should be reviewed today.

## The Ideal User Experience

EnglishAI should feel like a personal English coach that quietly studies the user's real communication and gives them a simple daily path.

The user should open the app and immediately see:

- Their most important improvement area today
- The exact words, verbs, expressions, or patterns to practice
- A short explanation of why this matters
- A focused practice session
- A clear sign of progress after finishing

The experience should avoid overwhelming the user with every possible correction. The product should be opinionated and selective.

## Product Dynamics to Build

### 1. Daily 20/80 Focus

Every day, generate a short "Today's Highest-Leverage Focus" section.

It should include:

- One primary weakness
- Three to ten target expressions or structures
- A short explanation based on the user's real writing or speaking
- Five to ten exercises
- A tiny before/after example using the user's style

Example:

```text
Today's focus: richer action verbs for product thinking.

You often write "improve", "make", and "help". These work, but they make your ideas sound more generic.

Practice:
- refine
- sharpen
- unlock
- reduce friction
- clarify
- prioritize
- turn into
```

### 2. Personal Vocabulary Graph

Build a vocabulary graph based on what the user actually says and writes.

The graph should identify:

- Words the user overuses
- Stronger alternatives
- Expressions that match the user's professional and personal topics
- Verbs that would improve clarity
- Connectors that would improve flow
- Phrases the user should stop translating literally

This should become one of the strongest differentiators of the product.

### 3. AI Coach Memory

The AI should keep a durable profile of the user's English.

Suggested profile sections:

- Communication style
- Common topics
- Recurring grammar mistakes
- Recurring vocabulary gaps
- Speaking patterns
- Writing patterns
- Current 20/80 priorities
- Recently mastered areas
- Next review areas

The coach should update this profile after each analysis and use it to generate better future feedback.

### 4. Practice Levels

Practice should have levels, but the levels should represent useful capability, not generic difficulty.

Suggested levels:

- **Level 1: Accuracy**: Fix obvious grammar and sentence errors.
- **Level 2: Clarity**: Make sentences shorter, cleaner, and easier to understand.
- **Level 3: Range**: Add stronger vocabulary, verbs, connectors, and expressions.
- **Level 4: Naturalness**: Make English sound less translated and more fluent.
- **Level 5: Presence**: Improve persuasive, professional, confident communication.

The app should decide which level matters most based on the user's actual data.

### 5. Coach Recommendations

The AI coach should generate recommendations like:

- "Stop practicing articles this week; your bigger issue is sentence flow."
- "You need more verbs for explaining product improvements."
- "Your spoken English is clear, but your written English needs richer connectors."
- "Practice 10 short rewrites instead of long essays."
- "Review this weakness again in 3 days."

The coach should be direct, selective, and useful.

### 6. Before and After Rewrites

For each analysis, show examples using the user's real style:

```text
Original:
I think we need to improve the onboarding because users don't understand fast.

Upgrade:
We should simplify onboarding because users are not reaching the key action quickly enough.
```

This helps the user see what better English looks like in their own context.

### 7. Speaking Coach Layer

Voice recordings and transcriptions should become a dedicated speaking improvement loop.

The coach should analyze:

- Sentence length while speaking
- Repeated filler phrases
- Verb variety
- Clarity of explanation
- Confidence and directness
- Overly literal phrasing

The product should help the user speak better in meetings, not only write better text.

### 8. Weekly Progress Review

The weekly review should not just summarize activity. It should tell the user:

- What improved this week
- What is still repeated
- Which weakness is now lower priority
- Which weakness is the new 20/80 focus
- Which expressions should be practiced next week

This turns progress tracking into coaching.

## Product Principles

- **Use the user's real English.** The best learning data comes from how the user already communicates.
- **Prioritize leverage.** Do not surface every mistake. Surface what matters most.
- **Teach expression, not only correction.** The user wants richer, clearer, more natural English.
- **Make practice specific.** Every exercise should connect to a known weakness or opportunity.
- **Keep the loop short.** Capture, analyze, recommend, practice, remember.
- **Reward progress.** Show what improved, not only what was wrong.
- **Respect privacy.** The app stores data locally and should make capture, recording, and analysis behavior transparent.

## Technical Summary

EnglishAI is a native Swift/SwiftUI macOS app.

Core components:

- `RecordManager`: Coordinates capture services and filtering.
- `KeyboardMonitorService`: Captures keyboard events through `CGEventTap`.
- `ClipboardMonitorService`: Detects Wispr Flow transcriptions.
- `AppFocusMonitorService`: Tracks active application context.
- `VoiceRecordingService`: Captures microphone recordings.
- `WhisperTranscriptionService`: Transcribes recordings with Whisper.
- `DatabaseService`: Stores records, insights, recordings, exercises, attempts, and progress in SQLite.
- `AIAnalysisService`: Sends captured English to Claude or OpenAI for analysis.
- `ExerciseGenerationService`: Generates personalized practice exercises.

Data is stored at:

```text
~/Library/Application Support/EnglishAI/records.sqlite
```

## Build and Development

Requirements:

- macOS 13.0 or later
- Xcode with command line tools
- Accessibility permission for keyboard capture
- Microphone permission for voice recording
- Anthropic or OpenAI API key for analysis and exercise generation

Useful files:

- `docs/PRODUCT.md`: Detailed product and technical registry.
- `docs/RECORDING_MECHANISMS.md`: Recording and filtering details.
- `tasks/prd-personalized-exercises.md`: Personalized exercise product requirements.
- `tasks/prd-voice-recording-transcription.md`: Voice recording and transcription requirements.

Build scripts:

- `create_installer.sh`: Build Release and create DMG installer.
- `create_pkg_installer.sh`: Create PKG installer.
- `quick_update.sh`: Quick build and open DMG for development testing.

## Product North Star

EnglishAI wins if the user feels:

> "This app knows exactly what I need to practice next to sound clearer, richer, and more natural in English."

Everything in the product should serve that. The recorder, analysis, exercises, progress tracking, and voice features are not separate modules. They are one learning loop designed to discover and train the user's personal 20/80.
