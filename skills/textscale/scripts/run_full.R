# Full pipeline once the prompt is final and audited: embed, annotate every
# design pair, fit on the training split, validate on held-out documents,
# refit on all pairs, and score every document with 95% intervals.
# Usage: Rscript run_full.R <run_dir> [--allow-no-audit]
#
# Writes: scores.csv, comparisons.csv, validation.txt, calibration.png
# (when the test set is large enough), result.rds (objects recenter.R uses).
# Scores are left exactly as the model produces them: log-odds units, with
# an arbitrary origin. No rescaling.

source(file.path(dirname(normalizePath(sub("--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "common.R"))

run_dir <- args_run_dir()
cfg     <- read_config(run_dir)
docs    <- load_run_documents(run_dir)
comp    <- readRDS(file.path(run_dir, "comparisons.rds"))

if (!identical(docs$content, load_documents(cfg)$content)) {
  stop("The input documents changed after prepare.R ran. Start a new run directory.", call. = FALSE)
}

# The full run must use the prompt the user audited.
aud <- latest_audit(run_dir, cfg)
if (is.null(aud)) {
  if (!"--allow-no-audit" %in% commandArgs(trailingOnly = TRUE)) {
    stop("No audit round yet. Run one (or pass --allow-no-audit if the user has decided to skip it).", call. = FALSE)
  }
  message("Proceeding without an audit round, at the user's request.")
} else if (!aud$matches) {
  stop("config.json no longer matches audit round '", aud$round, "' (prompt, annotator model, or ties). ",
       "The audited prompt is the one that should be run; draw a new audit round for the changed settings.", call. = FALSE)
} else if (!file.exists(main_cache(run_dir, cfg)) && file.exists(file.path(aud$dir, "annotations.rds"))) {
  # Same prompt and model as the audit, so its LLM answers are reused.
  file.copy(file.path(aud$dir, "annotations.rds"), main_cache(run_dir, cfg))
}

embeddings <- embed(docs, cfg, run_dir)

comp <- annotate(comp, cfg, cfg$prompt, cache = main_cache(run_dir, cfg), batch = isTRUE(cfg$use_batch))
bad <- is.na(comp$winner) | !comp$winner %in% c("A", "B", "tie")
if (all(bad)) stop("Every annotation failed; run check_keys.R --verify.", call. = FALSE)
if (any(bad)) {
  warning(sum(bad), " pair(s) with no usable LLM answer are dropped before fitting.", call. = FALSE)
  comp <- comp[!bad, ]
}

model_eval <- textscale::fit_model(comp, embeddings, method = "ridge")
validation <- textscale::validate_model(model_eval, comp, embeddings, force = isTRUE(cfg$force))
writeLines(capture.output(print(validation)), file.path(run_dir, "validation.txt"))
if (!is.na(validation$ici)) {
  grDevices::png(file.path(run_dir, "calibration.png"), width = 900, height = 750, res = 150)
  plot(validation)
  grDevices::dev.off()
}

model_final <- textscale::fit_model(comp, embeddings, method = "ridge", refit = TRUE)
sc <- textscale::score_documents(model_final, embeddings, ci = TRUE, ci_method = "laplace")

out <- data.frame(doc_id = docs$doc_id, label = docs$label,
                  score = sc$score, lower = sc$lower, upper = sc$upper)
if (!is.null(cfg$block_column)) out$block <- docs$block
if (cfg$document_type == "image") out$path <- docs$content else out$text <- docs$content
out <- out[order(-out$score), ]
write.csv(out, file.path(run_dir, "scores.csv"), row.names = FALSE, fileEncoding = "UTF-8")

write.csv(data.frame(pair_id = comp$pair_id,
                     label_a = docs$label[comp$doc_id_a], label_b = docs$label[comp$doc_id_b],
                     split = comp$split, winner = comp$winner),
          file.path(run_dir, "comparisons.csv"), row.names = FALSE, fileEncoding = "UTF-8")

saveRDS(list(model_final = model_final, model_eval = model_eval, validation = validation,
             embeddings = embeddings, comparisons = comp, docs = docs),
        file.path(run_dir, "result.rds"))

print(validation)
cat(sprintf("\nScored %d documents -> %s\nScore range %.2f to %.2f (log-odds units; origin arbitrary until recentered)\n",
            nrow(out), file.path(run_dir, "scores.csv"), min(out$score), max(out$score)))
