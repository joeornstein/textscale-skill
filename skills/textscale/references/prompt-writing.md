# Turning a calibration round into a better comparison question

Use this after each calibration round, alongside `disagreements.csv`. The aim is a question the user would endorse as saying what they mean. It is not to maximize agreement on these particular pairs: a question tuned until it reproduces 20 judgments has learned the pairs, not the concept, and the audit round will show it.

## What the question needs

- **One concept, one direction.** "Which ... has more X?" or "Which is more X?" Check that "more" has an unambiguous direction: is "more partisan" more extreme, or more aligned with a party?
- **The unit of judgment.** Say what is being judged when the document holds several things: the speaker or the statement, the whole image or the person in it, the argument's quality or its conclusion.
- **Scope, if needed.** A short definition after the question can say what counts and what doesn't ("Count only hostility toward the witness, not toward absent third parties"). The grandstanding application put a three-part rubric here.
- **Rules for recurring edge cases.** Write one only where the round showed a genuinely recurring case. Each rule should be something the user decided, not something you inferred from the LLM's answers.
- **No hints toward an answer.** Nothing about which position, party or side tends to score higher.

## Reading the round

Group the disagreements and notes into patterns before proposing wording. Common ones:

| Pattern | What it suggests |
|---|---|
| The user's notes keep naming a criterion the question doesn't mention | Add it to the question or definition, or confirm the user means to exclude it |
| Disagreements split along two different features (intensity vs. frequency, tone vs. topic) | The concept bundles two things. Ask the user which one they mean, or how the two combine |
| The LLM favors longer texts, higher-quality images, or a particular topic | Name it as irrelevant in the definition. If it persists, consider blocking or normalizing the documents |
| The user skips many pairs | Some documents may be outside the concept's scope. Filtering the corpus may beat rewording |
| The user ties often and the LLM rarely (or vice versa) | Decide what a tie should mean. Consider forced choice, or define "a meaningful difference" |
| Disagreements are scattered close calls with no pattern | The question may already be fine. Close pairs are hard for everyone, and the paper found agreement near chance for pairs under ~0.3 log-odds apart |

The last row matters most. Not every disagreement calls for a rewrite. If the disagreements are close calls and the user, looking at them, says "either answer is defensible", that is a sign the question is working.

## Proposing the revision

- **Show your reasoning.** Give the old and new wording side by side, and for each change, the pairs or notes that motivated it.
- **Keep it short.** A question of a sentence or two, with a definition of a few sentences if needed. Long rubrics invite the LLM to weigh criteria in its own way.
- **Let the user decide.** They change `prompt` in config.json, or tell you to. A new round snapshots whatever the config says at that moment.
