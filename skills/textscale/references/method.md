# The method, condensed

Source: Joseph T. Ornstein, "Scaling Documents with Pairwise Comparisons and Embeddings" (working paper; digest made from the September 2026 draft). PDF: https://joeornstein.github.io/publications/textscale.pdf. Cite the paper, not this digest. Check the current draft if something here seems out of date.

## Contents
- The model
- The six steps
- Reading the scores
- Uncertainty
- Validation, and what failure looks like
- Practical guidance from the applications

## The model

Each document i has a latent quantity θᵢ. Annotators (human or LLM) are good but imperfect: they compare reliably when θᵢ and θⱼ are far apart and approach chance as they converge. Formally, the log-odds of choosing i over j equals θᵢ − θⱼ (Bradley-Terry). The paper grounds this in psychophysics: since Thurstone (1927), discriminability has been known to depend on differences, not absolute levels.

Classic Bradley-Terry estimation needs many comparisons for every document, and the number of pairs grows quadratically. Semantic projection (scoring documents by projecting embeddings onto a direction) scales well, but needs researcher-chosen anchor words for the direction. The method combines them. It models θᵢ = xᵢ′β, where xᵢ is the document's embedding, and learns β from comparisons. Nearby documents in embedding space borrow strength from each other, and any embeddable document can be scored, including ones never compared.

## The six steps

1. **Embed** every document. The applications use 256-dimension `text-embedding-3-large`; images use `gemini-embedding-2` (3,072 dimensions).
2. **Partition** documents (not pairs) into train and test; 20% held out.
3. **Annotate** random pairs within the training set. Before fitting, check face validity on a subset and report intercoder reliability if there are multiple annotators.
4. **Fit** ridge logistic regression of the outcome on the embedding difference (xᵢ − xⱼ), with the penalty chosen by 10-fold cross-validation. The coefficient vector is the concept's direction.
5. **Validate** on held-out pairs: accuracy and calibration (integrated calibration index, ICI).
6. **Score**: θ̂ᵢ = xᵢ′β̂. Check face validity, and compare against existing measures where any exist.

Steps 3, 5 and 6 are the validation checkpoints.

## Reading the scores

They form an interval scale in log-odds units. A one-unit difference means a 73% chance the higher document is chosen; two units 88%; three units 95%. This is the main advantage over "ask-and-average" 0–100 ratings, which pile up at the extremes (Appendix B shows two ads both rated 5/100 that differ by 3 units). Rescaling destroys this interpretation. The origin carries no meaning by itself, so shifting it to a meaningful neutral point loses nothing.

In the image example, documents scoring near zero happened to be neutral expressions. That's a coincidence of that fit, not a property of the method, which is why the skill picks the zero point deliberately.

## Uncertainty

Each score gets a 95% interval from the model. Width reflects how much the training comparisons tell us about that region of embedding space: documents unlike anything in the training pairs get wide intervals. The intervals can be carried into downstream analyses, and they flag documents the model is unsure about. They do not capture annotator error or disagreement between annotators.

## Validation, and what failure looks like

textscale warns when held-out accuracy is low (below 65%) or the ICI exceeds 0.10. In the code, the accuracy check uses the upper bound of the accuracy interval, and it stops outright below 55% or when the ICI exceeds 0.20.

The argument-strength application is the paper's cautionary tale. The model was trained on two topics and tested on a third, and held-out accuracy was 55.8%, with probabilities off by 26 points on average. The within-topic scores still looked plausible. Without the held-out check, they would have been trusted. Some concepts (persuasiveness may be one) depend too much on context to sit on a single linear direction in embedding space.

## Practical guidance from the applications

- **Annotation volume.** A few thousand comparisons can score far larger corpora. The applications used 1,000 (images), 6,000, 10,000 and 40,000. Once fitted, scoring 1.03 million statements cost about $17 in embeddings.
- **Question wording.** Make it construct-specific and directional: "Which sentence is further to the right politically?", "Which argument is more likely to persuade a listener to change their position?", "Which member of Congress has a bigger smile in their portrait?" For grandstanding, the comparison used Park's three-part rubric.
- **Remove proxies.** Strip cues that could stand in for the concept: party labels and politicians' names were removed before judging ideology.
- **Block on confounds.** Compare only within groups when a grouping could bias judgments (arguments compared only within topic and side).
- **Position bias is small but real.** GPT-5.2 picked the first-listed item 53.7% of the time versus 50.6% for humans. textscale randomizes A/B order.
- **LLM vs. human.** On ad tone, GPT-5.2 agreed with crowd coders on 81.6% of pairs, against roughly 79% human-human agreement. Agreement was near chance for pairs less than 0.3 units apart and about 99% for well-separated pairs, so most disagreements are genuinely close calls.
- **Dimensionality.** Accuracy plateaus around 256 dimensions; the ridge penalty discounts extra dimensions.
- **Coverage.** Training documents should span the range of variation expected wherever the model will be applied.
- **Scope of researcher choice.** The researcher's main choices are the embedding model and the annotator, and both can be justified with accuracy and reliability metrics.
