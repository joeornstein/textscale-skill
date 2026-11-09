# Estimate the annotator cost of the full run before anything is spent.
# Usage: Rscript estimate_cost.R <run_dir>
# Uses textscale's own (internal) price table and token approximations, and
# excludes pairs the full run will take from cache (the latest audit round,
# when its prompt and model still match config.json).

source(file.path(dirname(normalizePath(sub("--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "common.R"))

run_dir <- args_run_dir()
cfg     <- read_config(run_dir)
comp    <- readRDS(file.path(run_dir, "comparisons.rds"))

hit <- cache_hits(main_cache(run_dir, cfg), comp, cfg, cfg$prompt)
aud <- latest_audit(run_dir, cfg)
if (!is.null(aud) && aud$matches) hit <- hit | cache_hits(file.path(aud$dir, "annotations.rds"), comp, cfg, cfg$prompt)
todo <- comp[!hit, ]
sp   <- system_prompt_for(cfg, cfg$prompt)
batch <- isTRUE(cfg$use_batch)

msg <- if (cfg$document_type == "image") {
  textscale:::.cost_estimate_message_image(nrow(todo), sp, cfg$llm_model, batch = batch)
} else {
  textscale:::.cost_estimate_message(paste0("A: ", todo$text_a, "\nB: ", todo$text_b), sp, cfg$llm_model, batch = batch)
}

cat(sprintf("Pairs to annotate: %s (%s already cached)\n",
            format(nrow(todo), big.mark = ","), format(sum(hit), big.mark = ",")))
cat(if (is.null(msg)) sprintf("No price on file in textscale for '%s'; cannot estimate.\n", cfg$llm_model) else paste0(msg, "\n"))
cat(sprintf("Embeddings: %d document(s) with %s (usually a small fraction of the annotation cost).\n",
            nrow(load_run_documents(run_dir)), cfg$embedding_model))
if (batch) cat("Batch mode is on: half price, but results can take hours to come back.\n")
