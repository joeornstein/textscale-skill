# Models and API keys

## Annotator (the LLM that judges pairs)

textscale's `annotate_comparisons()` calls OpenAI via `ellmer::chat_openai()`, so the annotator must be an OpenAI chat model. Default: `gpt-5.4-mini`, the model behind the paper's grandstanding and image applications.

textscale's price table, used by `estimate_cost.R`, covers these models:

- gpt-6: `gpt-6-astra`, `gpt-6-sol`, `gpt-6-terra`, `gpt-6-luna`
- gpt-5 series: `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.4-nano`, `gpt-5.2`, `gpt-5.1`, `gpt-5`, `gpt-5-mini`, `gpt-5-nano`
- older: `gpt-4.1`, `gpt-4.1-mini`, `gpt-4.1-nano`, `gpt-4o`, `gpt-4o-mini`

Other OpenAI model names work, but get no cost estimate. To see the current prices, run `textscale:::.model_prices`.

Choosing:

- **Larger models** tend to judge subtle concepts better and cost more per pair.
- **Image pairs** cost far more than short text pairs, since each image is roughly 1,500 input tokens at high detail.
- **Use the audit to decide.** If agreement is adequate with the cheaper model, that is the evidence for using it. Switching models after the audit means auditing again, because agreement is a property of the model plus the prompt.

Key: `OPENAI_API_KEY`.

## Embedding model

| Documents | Default | Provider / key | Alternatives |
|---|---|---|---|
| Text | `text-embedding-3-large`, 256 dims | OpenAI / `OPENAI_API_KEY` | `text-embedding-3-small`; other dims via `embedding_dimensions` (Matryoshka truncation); `mistral-embed` (Mistral / `MISTRAL_API_KEY`, always 1,024 dims); any OpenRouter embedding model named `org/model` (`OPENROUTER_API_KEY`) |
| Images | `google/gemini-embedding-2` | OpenRouter / `OPENROUTER_API_KEY` | other OpenRouter multimodal embedding models that accept images |

On dimensions, the paper found accuracy on ad tone plateaus around 256 dimensions. 2,048 dimensions gained under 2 points, and the ridge penalty discounted the extra dimensions. 256 is a sound default; going higher is a robustness check, not an upgrade.

Embeddings are cached per model (`embeddings_<model>.rds` in the run directory), so switching models never mixes vectors. textscale's own `get_embeddings()` cache is keyed only by document, which is why the scripts name the cache file after the model.

## Installing keys

Keys belong in the user's `.Renviron`, written by the user themselves. Never ask for a key in the conversation. The user runs one of these in their own R console, pasting the key in place of `...`. fuzzylink is installed alongside textscale.

```r
fuzzylink::openai_api_key("...", install = TRUE)
fuzzylink::openrouter_api_key("...", install = TRUE)
fuzzylink::mistral_api_key("...", install = TRUE)
```

Each appends `KEY=value` to `~/.Renviron` and backs up the old file to `~/.Renviron_backup`. To replace an existing key, add `overwrite = TRUE`. The key takes effect in new R sessions, so `Rscript` picks it up immediately.

Alternatively, `usethis::edit_r_environ()` opens `~/.Renviron` in an editor, where the user can add a line such as `OPENAI_API_KEY=sk-...`. The file must end with a newline.

Where to get keys:
- OpenAI: https://platform.openai.com/api-keys
- OpenRouter: https://openrouter.ai/keys
- Mistral: https://console.mistral.ai/api-keys/

## Where R looks

At startup R reads the first of these that exists:

1. The file named by `R_ENVIRON_USER`.
2. `.Renviron` in the current working directory.
3. `~/.Renviron`.

A project-level `.Renviron` therefore hides everything in the home one. `check_keys.R` prints which file the session used and whether one in the working directory is shadowing the home file. Keys exported in a shell profile also reach R, but only from shells that read that profile, so `.Renviron` is more dependable.

`check_keys.R --verify` makes one free, read-only request per provider to confirm each key is accepted:

- OpenAI: list models.
- OpenRouter: key info.
- Mistral: list models.

A 401 means the key is wrong or revoked. For OpenRouter, a valid key with no credit can still pass this check but fail on the first embedding call.
