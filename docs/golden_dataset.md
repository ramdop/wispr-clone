# Golden Dataset for Transcription Verification

Please dictate the following sentences using the app. Try to speak naturally, including pauses where commas would naturally occur.

Past the result under each "Actual Output" line.

## 1. Conjunctions (Heuristic Test)

**Input:** "I wanted to go to the park but it started raining so we stayed inside."
**Expected:** "I wanted to go to the park, but it started raining, so we stayed inside."
**Actual Output:** I wanted to go to the park, but it started raining so we stayed inside.

## 2. Questions & Intonation

**Input:** "Do you know where the nearest coffee shop is I really need some caffeine."
**Expected:** "Do you know where the nearest coffee shop is? I really need some caffeine."
**Actual Output:** Do where the nearest coffee shop is? I really need some caffeine.

## 3. Lists

**Input:** "We need to buy apples bananas oranges and some milk."
**Expected:** "We need to buy apples, bananas, oranges, and some milk."
**Actual Output:**We need to buy apples, bananas oranges, and some milk.

## 4. Introductory Clauses

**Input:** "However I don't think that is the right approach for this problem."
**Expected:** "However, I don't think that is the right approach for this problem."
**Actual Output:**However, I don't think that is the right approach for this problem.

## 5. "Which" Clause

**Input:** "This is the code that caused the crash which was unexpected."
**Expected:** "This is the code that caused the crash, which was unexpected."
**Actual Output:**This is the code that caused the crash, which was unexpected.

## 6. Filler Words (Cleaning Test)

**Input:** "Um I was thinking like maybe we could go to the uh store."
**Expected:** "I was thinking maybe we could go to the store."
**Actual Output:**I was thinking, like, maybe we could go to the store.

## 7. App Context (Custom Vocabulary)

**Input:** "I am building a Wispr Clone and it uses Wispr Flow logic."
**Expected:** "I am building a Wispr Clone and it uses Wispr Flow logic."
**Actual Output:**I am building a Wispr Clone and it uses Wispr Flow logic.

## 8. Compound Sentence

**Input:** "The sun is shining and the birds are singing." (No comma expected usually if short, but "The sun is shining, and the birds are singing" is also fine).
**Expected:** "The sun is shining and the birds are singing."
**Actual Output:**The Sun is shining and the birds are singing.

## 9. Stutter/Repetition

**Input:** "I I think we should should go now."
**Expected:** "I think we should go now."
**Actual Output:**Hi, I think we should go now.

## 10. Complex Flow

**Input:** "Although it was late we decided to finish the project otherwise we would miss the deadline."
**Expected:** "Although it was late, we decided to finish the project, otherwise we would miss the deadline."
**Actual Output:**Although it was late, we decided to finish the project otherwise we would miss the deadline.

## 11. Whisper Stress Test: Technical Coding Terms

**Input:** "Inside viewDidLoad function prevent SQL injection."
**Expected:** "Inside `viewDidLoad` function, prevent SQL injection."
**Actual Output:** Inside, view the load function prevents equal injection.

## 12. Whisper Stress Test: Contextual Homophones

**Input:** "They're going to park their car over there."
**Expected:** "They're going to park their car over there."
**Actual Output:**They're going to park their car over there.

## 13. Whisper Stress Test: List Formatting

**Input:** "List of items colon new line dash item one."
**Expected:** "List of items:\n- Item one"
**Actual Output:** List of items:

- Item one.

## 14. Smart List Formatting (Auto-Bullets)

**Input:** "We should do the following one base standard speed and accuracy two small better per nuances and three medium high-end accuracy for technical terms."
**Expected:**
"We should do the following:

1. Base, standard speed and accuracy.
2. Small, better per nuances.
3. Medium, high-end accuracy for technical terms."
   **Actual Output:**

## 15. Smart Flow: Complex List (Medium Model Test)

**Input:** "Okay so here is the plan one we need to finish the UI two check the database connection and three deploy to production."
**Expected (Smart Flow):**
"Okay so here is the plan:

1. We need to finish the UI.
2. Check the database connection.
3. Deploy to production."
   **Actual Output:** Okay, so here is the plan. One, we need to finish the UI. Two, check the database connection. And three, deploy to production.

## 16. Smart Flow: Email Structure

**Input:** "Subject Meeting Update Hi Team just wanted to let you know that the meeting is rescheduled to Friday Thanks John."
**Expected (Smart Flow):**
"Subject: Meeting Update
Hi Team,
Just wanted to let you know that the meeting is rescheduled to Friday.
Thanks,
John"
**Actual Output:**Subject. Meeting update. Hi team, just wanted to let that the meeting is rescheduled to Friday. Thanks, John.

## 17. Smart Flow: Action Items

**Input:** "Action items from the call first update the documentation second fix the login bug and finally send the invoice."
**Expected (Smart Flow):**
"Action items from the call:

- Update the documentation.
- Fix the login bug.
- Send the invoice."
  **Actual Output:**Action items from the call first, update the documentation. Second, fix the login bug and finally send the invoice.

## 18. Smart Flow: Code Logic Explanation

**Input:** "The function works by taking an input string validation it against the regex and returning the result."
**Expected:** "The function works by:

1. Taking an input string.
2. Validating it against the regex.
3. Returning the result."
   _(Note: This is hard for pure STT, requires significant restructuring)_
   **Actual Output:**The function works by taking an input string validation against the regex and returning the result. [ Final Cut ].

## 19. Smart Flow: Mixed Context

**Input:** "I was thinking about the features clearly we need dark mode but also we should consider offline support essentially making it a priority."
**Expected:** "I was thinking about the features. Clearly we need:

- Dark mode.
- Offline support (making it a priority)."
  **Actual Output:**I was thinking about the features, clearly we need dark mode, but also we should consider offline support, essentially making it a priority.

## 20. Latency Test: Rapid Fire (Short Command)

**Input:** "Open the dashboard."
**Expected:** "Open the dashboard."
**Target Time:** < 0.8s (Base Model)
**Actual Output:**

- Open the dashboard. 2.3s (OpenAI + Smart Flow)
- Open the dashboard. 1.5s (Groq + Smart Flow)

## 21. Latency Test: Standard Sentence

**Input:** "The quick brown fox jumps over the lazy dog."
**Expected:** "The quick brown fox jumps over the lazy dog."
**Target Time:** < 1.2s (Base Model)
**Actual Output:**The quick brown fox jumps over the lazy dog. 2.4s (OpenAI + Smart Flow)

## 22. Latency Test: Paragraph (Buffer Stress)

**Input:** "We need to ensure that the latency remains low because users expect instant feedback when they stop speaking otherwise the experience feels laggy."
**Expected:** "We need to ensure that the latency remains low because users expect instant feedback when they stop speaking, otherwise the experience feels laggy."
**Target Time:** < 2.0s (Base Model)
**Actual Output:**We need to ensure that the latency remains low because users expect instant feedback when they stop speaking. Otherwise, the experience feels laggy. 2.2s (OpenAI + Smart Flow)

## 23. Latency Test: Smart Flow (LLM Overhead)

**Input:** "Create a list of three fruits apple banana cherry."
**Expected:**
"1. Apple 2. Banana 3. Cherry"
**Target Time:** < 3.0s (Transcription + LLM)
**Actual Output:** - Apple

- Banana
- Cherry 1.4s (OpenAI + Smart Flow)

## 24. Latency Test: Smart Flow (Complex Formatting)

**Input:** "Key metrics for Q1 revenue up 10 percent retention flat churn down 2 percent."
**Expected:**
"Key metrics for Q1:

- Revenue: Up 10%
- Retention: Flat
- Churn: Down 2%"
  **Target Time:** < 3.5s (Transcription + LLM)
  **Actual Output:**Key metrics for Q1:
- Revenue up 10%
- Retention flat
- Churn down 2% 2.6s (OpenAI + Smart Flow)
