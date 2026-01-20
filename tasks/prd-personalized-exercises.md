# PRD: Personalized English Exercises

## Introduction

Add an AI-powered exercise system that generates personalized English practice based on each user's specific mistakes and weaknesses identified through analysis. The system creates targeted exercises across multiple formats, tracks progress over time, and uses spaced repetition to reinforce areas that need improvement.

This feature transforms EnglishAI from a passive analysis tool into an active learning platform where users can practice and improve the specific English skills they struggle with.

## Goals

- Generate exercises that directly target user's identified weaknesses from AI analysis
- Support 8 exercise types to address different learning styles and skill areas
- Provide both daily suggested practice and on-demand exercise generation
- Track exercise performance to measure improvement over time
- Implement spaced repetition to reinforce weak areas at optimal intervals
- Deliver simple, clear feedback (correct/incorrect + brief explanation)

## User Stories

### US-001: Exercise Data Models
**Description:** As a developer, I need database models to store exercises, attempts, and progress so the system can track learning over time.

**Acceptance Criteria:**
- [ ] Create `Exercise` model with: id, type, instruction, content (JSON), difficulty (1-5), targetWeakness, createdAt, sourceAnalysisId
- [ ] Create `ExerciseAttempt` model with: id, exerciseId, userAnswer (JSON), isCorrect, feedback, attemptedAt, timeSpentSeconds
- [ ] Create `WeaknessProgress` model with: id, weaknessCategory, totalAttempts, correctAttempts, lastPracticed, nextReviewDate, masteryLevel (0-100)
- [ ] Add SQLite tables with proper indexes
- [ ] Typecheck/lint passes

### US-002: Exercise Type Definitions
**Description:** As a developer, I need Swift models that define all 8 exercise types so AI output can be decoded and rendered.

**Acceptance Criteria:**
- [ ] Define `ExerciseType` enum: singleChoice, multipleChoice, fillInBlank, freeResponse, errorCorrection, sentenceReorder, matching, wordFormation
- [ ] Define `ExerciseContent` as enum with associated values for each type
- [ ] Define specific structs for each type:
  - `SingleChoiceExercise`: question, options[], correctIndex
  - `MultipleChoiceExercise`: question, options[], correctIndices[]
  - `FillInBlankExercise`: textWithBlanks, blanks[] (position, correctAnswer, acceptableAlternatives[])
  - `FreeResponseExercise`: prompt, sampleAnswer, keyPoints[]
  - `ErrorCorrectionExercise`: incorrectSentence, errors[] (position, incorrect, correct, explanation)
  - `SentenceReorderExercise`: shuffledWords[], correctOrder[]
  - `MatchingExercise`: leftItems[], rightItems[], correctPairs[]
  - `WordFormationExercise`: baseSentence, targetWord, correctForm, wordFamily[]
- [ ] All models conform to Codable for JSON serialization
- [ ] Typecheck/lint passes

### US-003: Exercise Generation Service
**Description:** As a developer, I need a service that calls the AI to generate exercises based on user's analysis data.

**Acceptance Criteria:**
- [ ] Create `ExerciseGenerationService` class
- [ ] Method `generateExercises(from analysis: Analysis, count: Int, types: [ExerciseType]?, difficulty: Int?) -> [Exercise]`
- [ ] If difficulty is nil, randomize difficulty (1-5) for each exercise
- [ ] Uses structured output (JSON schema) to ensure valid exercise format
- [ ] AI prompt includes user's specific weaknesses, example mistakes, and target areas
- [ ] Validates AI response matches expected schema before returning
- [ ] Handles API errors gracefully with retry logic
- [ ] Typecheck/lint passes

### US-004: Daily Exercise Generation
**Description:** As a user, I want the app to suggest daily exercises based on my recent mistakes so I have a consistent practice routine.

**Acceptance Criteria:**
- [ ] Generate daily exercise set each day (triggered on app launch or manually)
- [ ] Daily set contains 5-10 exercises based on recent analysis (last 7 days)
- [ ] Prioritizes weakness areas that haven't been practiced recently (spaced repetition)
- [ ] Mix of exercise types weighted toward user's weak areas
- [ ] Difficulty is randomized across the set (1-5)
- [ ] Stores generated exercises in database with `dailySetDate` field
- [ ] Daily exercises do not expire - remain available until completed
- [ ] Typecheck/lint passes

### US-005: On-Demand Exercise Generation
**Description:** As a user, I want to request additional exercises anytime so I can practice more when motivated.

**Acceptance Criteria:**
- [ ] "Generate More Exercises" button in exercise view
- [ ] User can select focus area (specific weakness) or let AI choose
- [ ] User can select exercise count (5, 10, 15)
- [ ] User can optionally select difficulty (1-5); if not selected, difficulty is randomized
- [ ] Shows loading indicator during generation
- [ ] Generated exercises appear in exercise list
- [ ] Typecheck/lint passes

### US-006: Exercise List View
**Description:** As a user, I want to see my available exercises so I can choose what to practice.

**Acceptance Criteria:**
- [ ] New "Practice" tab/section in main navigation
- [ ] Shows daily exercises section at top with progress indicator (e.g., "3/8 completed")
- [ ] Groups exercises by weakness category
- [ ] Each exercise card shows: type icon, brief description, difficulty stars, completion status
- [ ] Filter by: All, Incomplete, Completed, By Type
- [ ] Typecheck/lint passes

### US-007: Single Choice Exercise View
**Description:** As a user, I want to answer single choice questions so I can test my grammar/vocabulary knowledge.

**Acceptance Criteria:**
- [ ] Display question text prominently
- [ ] Show 4 options as tappable buttons/cards
- [ ] Selected option highlights before submission
- [ ] "Check Answer" button to submit
- [ ] After submission: correct answer shows green, wrong shows red with correct highlighted
- [ ] Brief explanation appears below options
- [ ] "Next Exercise" button to continue
- [ ] Typecheck/lint passes

### US-008: Multiple Choice Exercise View
**Description:** As a user, I want to select multiple correct answers so I can practice identifying all valid options.

**Acceptance Criteria:**
- [ ] Display question with instruction "Select all that apply"
- [ ] Checkboxes instead of radio buttons
- [ ] User can select/deselect multiple options
- [ ] "Check Answer" button to submit
- [ ] After submission: shows which selections were correct/incorrect
- [ ] Partial credit feedback (e.g., "2 of 3 correct")
- [ ] Typecheck/lint passes

### US-009: Fill in the Blank Exercise View
**Description:** As a user, I want to complete sentences by filling in missing words so I can practice contextual vocabulary and grammar.

**Acceptance Criteria:**
- [ ] Display sentence with blank spaces (underlined or boxed areas)
- [ ] Tap blank to focus text input for that blank
- [ ] Support multiple blanks per sentence
- [ ] "Check Answer" button to submit all blanks
- [ ] Accept alternative correct answers (e.g., "don't" and "do not")
- [ ] After submission: show correct/incorrect for each blank
- [ ] Typecheck/lint passes

### US-010: Free Response Exercise View
**Description:** As a user, I want to write open-ended responses so I can practice expressing ideas in English.

**Acceptance Criteria:**
- [ ] Display prompt/question clearly
- [ ] Multi-line text input area
- [ ] Character count indicator
- [ ] "Submit for Review" button
- [ ] AI evaluates response and returns: correct/incorrect + brief explanation
- [ ] Show sample answer after submission for comparison
- [ ] Typecheck/lint passes

### US-011: Error Correction Exercise View
**Description:** As a user, I want to find and fix errors in sentences so I can practice identifying common mistakes.

**Acceptance Criteria:**
- [ ] Display sentence with error(s)
- [ ] User taps on the word they think is wrong
- [ ] After selecting word, show text input to type correction
- [ ] Support sentences with multiple errors
- [ ] "Check Answer" button to submit
- [ ] After submission: highlight all errors with explanations
- [ ] Typecheck/lint passes

### US-012: Sentence Reorder Exercise View
**Description:** As a user, I want to arrange scrambled words into correct sentences so I can practice word order.

**Acceptance Criteria:**
- [ ] Display scrambled words as draggable tiles
- [ ] Drag-and-drop to reorder (or tap to select then tap position)
- [ ] Clear visual feedback during drag
- [ ] "Check Answer" button to submit
- [ ] After submission: show correct order if wrong
- [ ] Typecheck/lint passes

### US-013: Matching Exercise View
**Description:** As a user, I want to match related items (e.g., words to definitions) so I can build vocabulary connections.

**Acceptance Criteria:**
- [ ] Two columns: left items and right items
- [ ] Tap left item, then tap right item to create match
- [ ] Visual line or highlight connects matched pairs
- [ ] Ability to remove a match by tapping it
- [ ] "Check Answer" button when all items matched
- [ ] After submission: show correct/incorrect for each pair
- [ ] Typecheck/lint passes

### US-014: Word Formation Exercise View
**Description:** As a user, I want to practice using correct word forms (noun/verb/adjective) so I can improve my grammar.

**Acceptance Criteria:**
- [ ] Display sentence with a word that needs to be changed
- [ ] Show the base word that needs transformation (e.g., "BEAUTY")
- [ ] Text input for user to type the correct form
- [ ] "Check Answer" button to submit
- [ ] After submission: show correct form and word family (beautify, beautiful, beautifully)
- [ ] Typecheck/lint passes

### US-015: Exercise Attempt Recording
**Description:** As a developer, I need to record every exercise attempt so progress can be tracked.

**Acceptance Criteria:**
- [ ] Record attempt when user submits any exercise
- [ ] Store: exerciseId, userAnswer, isCorrect, feedback, attemptedAt, timeSpentSeconds
- [ ] Track time from exercise display to submission
- [ ] Handle partial correctness for multi-part exercises (store percentage)
- [ ] Update exercise completion status
- [ ] Typecheck/lint passes

### US-016: Weakness Progress Tracking
**Description:** As a developer, I need to update weakness progress after each attempt so spaced repetition works.

**Acceptance Criteria:**
- [ ] After each attempt, update WeaknessProgress for relevant category
- [ ] Increment totalAttempts and correctAttempts
- [ ] Update lastPracticed timestamp
- [ ] Calculate new masteryLevel based on recent performance (weighted recent attempts higher)
- [ ] Calculate nextReviewDate using spaced repetition algorithm:
  - If correct: increase interval (1 day → 3 days → 7 days → 14 days → 30 days)
  - If incorrect: reset to 1 day
- [ ] Typecheck/lint passes

### US-017: Progress Dashboard View
**Description:** As a user, I want to see my overall progress so I can track my improvement.

**Acceptance Criteria:**
- [ ] Progress section in Practice tab or separate view
- [ ] Overall stats: total exercises completed, accuracy percentage, current streak
- [ ] Weakness breakdown: list of categories with mastery level bars (0-100%)
- [ ] Trend chart: accuracy over last 7/30 days
- [ ] "Areas to Focus" section highlighting lowest mastery categories
- [ ] Typecheck/lint passes

### US-018: Spaced Repetition Integration
**Description:** As a user, I want exercises to focus on areas I'm struggling with at optimal intervals so I learn efficiently.

**Acceptance Criteria:**
- [ ] Daily exercise generation prioritizes weaknesses where nextReviewDate <= today
- [ ] Lower mastery areas get more exercises
- [ ] Recently mastered areas (>80%) get fewer exercises
- [ ] Difficult exercises (ones user got wrong) reappear sooner
- [ ] User can see "due for review" indicator on weakness categories
- [ ] Typecheck/lint passes

### US-019: Exercise Session Flow
**Description:** As a user, I want a smooth flow between exercises so practice feels engaging.

**Acceptance Criteria:**
- [ ] "Start Practice" button begins session with first exercise
- [ ] "Next" button after each exercise moves to next
- [ ] Progress bar shows position in session (e.g., "4 of 10")
- [ ] Session summary at end: exercises completed, accuracy, time spent
- [ ] Option to continue with more exercises or finish
- [ ] Typecheck/lint passes

### US-020: Exercise Generation Prompt Engineering
**Description:** As a developer, I need well-crafted prompts that generate high-quality, targeted exercises.

**Acceptance Criteria:**
- [ ] System prompt explains exercise format and JSON schema
- [ ] Includes user's specific mistakes as examples to target
- [ ] Includes weakness categories to focus on
- [ ] Specifies difficulty level appropriate to user's current mastery
- [ ] Requests exercises that feel natural and practical (not textbook-like)
- [ ] Includes examples of good exercises for each type
- [ ] Typecheck/lint passes

## Functional Requirements

- FR-1: System must generate exercises based on AI analysis data identifying user's specific weaknesses
- FR-2: System must support 8 exercise types: single choice, multiple choice, fill in blank, free response, error correction, sentence reorder, matching, word formation
- FR-3: System must use AI structured output to generate exercises in valid JSON format matching Swift models
- FR-4: System must generate a daily exercise set of 5-10 exercises on app launch
- FR-5: System must allow on-demand exercise generation with user-selected focus area, count, and optional difficulty (1-5); if difficulty not selected, randomize
- FR-6: System must record every exercise attempt with answer, correctness, feedback, and time spent
- FR-7: System must track progress per weakness category including mastery level (0-100%)
- FR-8: System must implement spaced repetition algorithm to schedule weakness reviews
- FR-9: System must provide simple feedback for each exercise: correct/incorrect + brief explanation
- FR-10: System must use AI to evaluate free response exercises and provide feedback
- FR-11: System must display progress dashboard with accuracy trends and weakness breakdown
- FR-12: System must prioritize exercises for weaknesses due for review based on spaced repetition schedule

## Non-Goals (Out of Scope)

- No audio/pronunciation exercises (future feature)
- No multiplayer or social features
- No gamification beyond progress tracking (no points, badges, leaderboards)
- No offline exercise generation (requires API)
- No exercise sharing or export
- No custom exercise creation by users
- No integration with external learning platforms
- No detailed coaching feedback (keeping feedback simple per requirements)

## Design Considerations

### UI/UX Requirements
- Practice tab should feel distinct from analysis/records views
- Exercise cards should be visually engaging with clear type indicators
- Progress visualizations should be motivating (progress bars, streaks)
- Exercise views should be focused and distraction-free
- Touch targets must be large enough for comfortable interaction
- Clear visual feedback for correct/incorrect answers

### Native macOS Considerations
- Use standard SwiftUI components where possible
- Support keyboard navigation for power users
- Drag-and-drop should feel native (sentence reorder, matching)
- Respect system appearance (light/dark mode)

## Technical Considerations

### AI Integration
- Extend existing `AIAnalysisService` or create new `ExerciseGenerationService`
- Use Claude/OpenAI structured output feature for guaranteed JSON schema
- Prompt must include JSON schema and examples for each exercise type
- Implement retry logic for malformed responses
- Consider caching generated exercises to reduce API calls

### Data Storage
- Extend existing SQLite database with new tables
- Use same threading pattern (serial queue `com.englishai.database`)
- Indexes on: exerciseId, weaknessCategory, nextReviewDate, dailySetDate

### Spaced Repetition Algorithm
- Use simplified SM-2 algorithm variant
- Intervals: 1, 3, 7, 14, 30 days for consecutive correct answers
- Reset to 1 day on incorrect answer
- Mastery level = weighted average of recent attempts (decay older attempts)

### Performance
- Lazy load exercise content (don't decode all at once)
- Prefetch next exercise while user completes current
- Background generation for daily exercises

## Success Metrics

- Users complete at least 5 exercises per session on average
- Daily exercise completion rate > 60%
- Weakness mastery levels increase over 30-day period
- Free response AI evaluation returns in < 3 seconds
- Exercise generation completes in < 10 seconds for a set of 10

## Design Decisions

1. **Exercises do not expire** - Daily exercises remain available until completed
2. **Reactive only** - Exercises are generated only for identified weaknesses (no proactive learning)
3. **No minimum data requirement** - Generate exercises from any available analysis
4. **No skip option** - Users complete exercises or leave them for later
5. **User-selected difficulty** - Optional difficulty selector (1-5) before generation; if not selected, random difficulty
