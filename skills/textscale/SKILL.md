---
name: textscale
description: Measure a continuous concept across a set of documents (texts or images) with the textscale R package (github.com/joeornstein/textscale) - pairwise comparisons by an LLM, a ridge model on embeddings, scores with 95% intervals on an interpretable log-odds scale. The user judges pairs themselves in a local browser page first, both to sharpen the concept and comparison question and to audit the LLM (Cohen's kappa) before the full run. Use this whenever someone wants to rank, rate, score, scale or measure texts, sentences, speeches, posts or images on some attribute ("which of these is more X", "put these on a scale of Y", "pairwise comparisons", "Bradley-Terry", "latent scale", "document scaling"), mentions textscale, or wants to check an LLM's comparative judgments against their own, even if they don't name the package.
---

# Scaling documents with textscale

The user brings a set of documents (a folder of images, a folder of text files, or a CSV with a text column) and a concept they want to measure. textscale has an LLM answer "which of these two has more of the concept?" for thousands of pairs, learns the direction in embedding space that predicts the answers, and scores every document along it. The method and its reasoning are in the paper; read `references/method.md` when you need to explain what the scores mean or why a step exists.

The user's own judgments do two jobs, in this order:

1. **Calibration rounds** sharpen the concept. Judging real pairs is where vague concepts meet hard cases ("is a forced smile a smile?", "does a long, mild critique count as more negative than a short, harsh one?"). The user's choices and notes, set against the LLM's, are the material for a precise comparison question.
2. **An audit round** measures how well the LLM applies the final question, on fresh pairs the user judges blind. This is the intercoder reliability the user can report. Keeping it separate from the rounds used to tune the prompt matters: agreement on pairs that shaped the wording is optimistically biased, for the same reason training accuracy flatters a model.

Only after the audit does the full run spend real money.

Scripts live in `scripts/` next to this file. The R scripts take the run directory as their first argument. Run them all from the same working directory (see step 2 on why).

## 1. Understand the task

Establish, asking only for what isn't already clear:

- **The documents.** Folder of images (jpg, png, webp, gif), folder of `.txt`/`.md` files, or a CSV (which column holds the text, and an id column if there is one). Note roughly how many there are and, for text, how long they are.
- **The concept, in the user's words.** Don't polish it yet; that's what calibration is for. Do help turn it into a first-draft comparison question: one sentence asking which of two documents has *more* of the concept ("Which statement is a clearer case of grandstanding?"). The same question goes to the LLM and appears on the user's judging page, so both judges answer the identical question.
- **Confounds worth blocking on.** If some grouping could drive the judgments instead of the concept (party, topic, the speaker's side), suggest comparing only within groups (`block_column`). The paper does this for argument strength: liberal arguments are only compared with liberal ones on the same topic. Also suggest stripping identity cues from texts when they could stand in for the concept (the paper removes party labels and names before judging ideology).
- **Ties.** Default: allowed (the judge may say neither has more). Ties are dropped before fitting. A forced choice is the alternative.
- **Design size.** Package default is 10,000 training and 5,000 test pairs. The paper's applications used 1,000 to 40,000; the image example reached 88% held-out accuracy with 1,000. With n documents there are only n(n-1)/2 distinct pairs. Small sets (under ~50 documents) give few test pairs, so held-out accuracy gets a wide interval and the calibration check (needs 50 test pairs) is skipped; say so up front.

## 2. Models and API keys

Ask the user to choose two models, offering the defaults (details and alternatives in `references/models-and-keys.md`):

- **Annotator LLM:** default `gpt-5.4-mini`. textscale calls OpenAI for annotation, so this must be an OpenAI model. Bigger models cost more per pair; the audit is how the user finds out whether the cheaper one is good enough.
- **Embedding model:** default `text-embedding-3-large` at 256 dimensions for text (OpenAI), `google/gemini-embedding-2` for images (via OpenRouter).

Write these into the run's `config.json` (step 3), then check the keys:

```
Rscript scripts/check_keys.R <run_dir> --verify
```

It reports which keys the chosen models need (`OPENAI_API_KEY`, plus `OPENROUTER_API_KEY` or `MISTRAL_API_KEY` depending on the embedder), whether each is visible to R, which environment file R read, and, with `--verify`, whether each provider accepts the key (one free read-only request each). It never prints a key.

If a key is missing or rejected, help the user install it. The key must never pass through this conversation: don't ask them to paste it here, and don't write it into files yourself. Instead, give them the line to run in their own R console with their key pasted in, for example `fuzzylink::openai_api_key("sk-...", install = TRUE)` (or `openrouter_api_key()`, `mistral_api_key()`; fuzzylink is installed with textscale). That appends the key to `~/.Renviron` and backs up the old file. Then re-run the check. Two things that commonly go wrong, both visible in the check's output:

- A `.Renviron` in the working directory makes R ignore `~/.Renviron` entirely. If the check says one is shadowing, either run the scripts from another directory or add the key to that file.
- A key exported in a shell profile is visible only to shells that read that profile. `.Renviron` is the reliable home for R.

Also confirm `Rscript -e 'packageVersion("textscale")'` works (if not, offer `pak::pak("joeornstein/textscale")`) and that `python3` exists.

## 3. Set up the run

Create a run directory next to the input, e.g. `<input folder or CSV's folder>/textscale_run_<YYYYMMDD-HHMM>/`, with `config.json`:

```json
{
  "input": "/abs/path/to/folder-or-file.csv",
  "document_type": "text",
  "text_column": "text",
  "id_column": "speech_id",
  "block_column": null,
  "prompt": "Which statement is a clearer case of grandstanding?",
  "allow_ties": true,
  "llm_model": "gpt-5.4-mini",
  "embedding_model": "text-embedding-3-large",
  "embedding_dimensions": 256,
  "n_train": 10000,
  "n_test": 5000,
  "prop": 0.8,
  "seed": 42
}
```

`document_type` is inferred if omitted. For folder input with blocks, add `"metadata_csv"` (a CSV with a `file` column and the block column). `text_column` and `id_column` apply to CSV input only.

Then `Rscript scripts/prepare.R <run_dir>`. It fixes the document order, refuses identical duplicate documents (textscale keys its caches by content, so duplicates would silently merge), and generates the comparison design. Every round's pairs are drawn from this design, so the user judges the same kind of pairs the model trains on, and the audit round's LLM answers can be reused in the full run.

## 4. Calibration rounds: sharpen the concept and the question

Each round:

1. `Rscript scripts/new_round.R <run_dir> cal1 20 calibration` (then `cal2`, ...). About 20 pairs is enough to surface the hard cases without tiring the user.
2. Start the judging page in the background (it keeps running across turns):
   `python3 scripts/judge_server.py --run-dir <run_dir> --round cal1 --open`
   (`--port` if 8765 is taken). Tell the user the URL and the keys (← A, → B, ↓ tie, S skip, N to type a note). Encourage notes on any pair that felt hard, odd, or not really about the concept; those notes are the most useful output of the round. Skip is for pairs that can't be compared on the concept at all, which is itself informative.
3. Meanwhile, run `Rscript scripts/round_llm.R <run_dir> cal1`. Don't reveal the LLM's answers until the user has finished: seeing them first would anchor their judgments.
4. When the user says they're done, stop the server (stop the background task or kill its PID; avoid `pkill -f`, which can match your own shell), run `Rscript scripts/agreement.R <run_dir> cal1`, and read `disagreements.csv` (every disagreement, skip, and noted pair, with the documents).

Then have the conversation the round is for. Go through the disagreements and notes with the user, showing the documents (view the images or quote the text). Look for:

- **What the user was actually weighing**, especially where it differs from the draft question's literal wording.
- **Two concepts bundled into one** (intensity vs. frequency, tone vs. content): the user may want to pick one or define how they combine.
- **Direction ambiguity**: what counts as "more"?
- **Things the LLM attends to that the user doesn't**, or the reverse (length, image quality, topic, a named person).
- **Skips**: are some documents outside the concept's scope? That may call for filtering the corpus rather than rewording.

`references/prompt-writing.md` has a checklist for turning this into wording. Propose a revised question (a short definition or rubric after the question is fine, as the paper does for grandstanding), and update `prompt` in `config.json` only once the user agrees.

Optionally run `round_llm.R <run_dir> cal1 --rerun` and `agreement.R <run_dir> cal1 --rerun` to see whether the revised wording resolves the disagreements. Say plainly that this is optimistic, since the revision was written with these pairs in view. If the conversation changed what the user means by the concept, they may want to revisit their own answers: the page's Review button lets them, and the last answer counts.

Repeat with a fresh round until the user is satisfied that the question says what they mean. Usually one to three rounds. Calibration agreement figures are for discussion, not reporting.

## 5. Audit round: reliability on held-out pairs

Once the question is final, draw a fresh round the prompt was never tuned on:

```
Rscript scripts/new_round.R <run_dir> audit 100 audit
```

Judging and LLM annotation work as in calibration, with the page in audit mode. Keep the LLM's answers entirely to yourself until the user has finished; this time it is what makes the figure a valid reliability estimate.

Report from `report.md`:

- Cohen's kappa (A / B / tie as categories) with its bootstrap interval and n. Lead with the interval: at n ≈ 100 it is wide, and the honest summary is often "consistent with anything from moderate to strong agreement."
- Raw agreement, the confusion matrix, and the decisive-pairs kappa.
- The A-choice rates, to spot a positional bias.

Avoid Landis-Koch style labels as if they were thresholds with standing. Point out structure in the confusion matrix (a judge who ties far more, disagreements concentrated in one direction), and offer to walk through the disagreements.

If the audit turns up a problem that changes the prompt, go back to calibration, and run a new audit round afterward: the old audit measured the old wording. `run_full.R` enforces this by refusing to run unless config.json still matches the latest audit round.

## 6. Full run (only with the user's go-ahead)

`Rscript scripts/estimate_cost.R <run_dir>` gives the number of pairs still to annotate and textscale's cost estimate. Tell the user and ask before proceeding. Mention `"use_batch": true` (half price via OpenAI's Batch API, but it can take hours).

On a yes, run `Rscript scripts/run_full.R <run_dir>` in the background with a long timeout and check on it. It embeds, annotates (audit pairs come from cache), fits on the training split, validates on held-out documents, refits on all pairs, and scores every document.

Validation policy is textscale's own. The checks use the upper bound of the accuracy interval:

- **Stops** when the upper bound is below 55%, or the ICI is above 0.20.
- **Warns** when the upper bound is below 65%, or the ICI is above 0.10.

On a stop, report the numbers and the calibration plot, and let the user decide: accept anyway (`"force": true` in config.json and rerun; annotations are cached, so it costs nothing), or revisit the concept. Don't set `force` yourself. The paper's argument-strength example is the cautionary case: plausible-looking scores, poor held-out accuracy.

## 7. Interpret, and choose a zero point

The scores are on the same footing as Bradley-Terry scores: the difference between two documents is the log-odds that the higher one is chosen. A gap of 1 means about 73% of the time, 2 about 88%, 3 about 95%. **Don't propose rescaling** (z-scores, 0–100, min-max): that throws away exactly this interpretation, and the spacing is the result.

The origin, though, is arbitrary, so offer to **recenter** so that zero means something. Ask the user what a neutral document would be for their concept, and whether the concept has a natural neutral point at all. Options, in order of preference when they fit:

- **Reference documents the user judges neutral** (one or several): `Rscript scripts/recenter.R <run_dir> --ref-docs 12,40,77` (or `--ref-labels`). Each score then reads as the log-odds of being chosen over a neutral document, and the intervals are recomputed to include uncertainty about where the reference sits. If the user can't name candidates, run `--preview` to show documents spread across the scale and let them point to where neutral falls.
- **A substantive baseline set** (a reference category or period), as reference documents.
- **A raw score value** the user chooses: `--value 1.3`.
- **The corpus median** (`--median`). This centers the distribution but isn't "neutral"; say so if the user picks it.

Then show the documents the script lists as nearest the new zero (view the images, quote the texts) and ask the user to confirm they look neutral. If they don't, adjust the anchor and look again. If the concept has no sensible neutral (pure magnitude with no meaningful middle), leave the origin alone and say why.

## 8. Deliver

In the run directory:

- **`scores.csv`**: one row per document (`doc_id`, `label`, `score`, `lower`, `upper`, plus `block` if blocked, and `text` or `path`), sorted high to low.
- **`scores_centered.csv` and `anchor.json`**, if recentered: centered columns plus `score_raw`.
- **Intervals.** They are Laplace intervals from the ridge posterior. They reflect how well the training comparisons pin down that region of embedding space, not disagreement between the LLM and a human.
- **`rounds/`**: every calibration and audit round, with the user's answers and notes, the LLM's answers, the prompt used, and the report. Together these are a record of how the concept was defined.
- **`validation.txt`, `calibration.png`**: held-out accuracy and calibration.
- **`comparisons.csv`**: every pair with the LLM's verdict.
- **`result.rds`**: the fitted model and embeddings. New documents of the same kind can be scored later without new comparisons.

Close with a short summary:

- the number of documents scored
- the final question
- the audit kappa with its interval
- held-out accuracy and ICI
- the zero point chosen
- anything that should make the user cautious
