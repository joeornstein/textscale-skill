# Have the LLM judge a round's pairs.
# Usage: Rscript round_llm.R <run_dir> <round> [--rerun]
#
# Default: uses the prompt snapshotted when the round was drawn; writes
#   llm.csv and caches to annotations.rds in the round folder.
# --rerun: uses the CURRENT prompt in config.json on the same pairs (to see
#   whether a revised prompt resolves the disagreements); writes
#   llm_rerun.csv and annotations_rerun.rds. Diagnostic only: those pairs
#   informed the revision, so agreement on them is optimistic.

source(file.path(dirname(normalizePath(sub("--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "common.R"))

a       <- commandArgs(trailingOnly = TRUE)
run_dir <- args_run_dir(); round <- a[2]; rerun <- "--rerun" %in% a
cfg     <- read_config(run_dir)
rdir    <- round_dir(run_dir, round)
meta    <- jsonlite::read_json(file.path(rdir, "meta.json"), simplifyVector = TRUE)
if (!identical(meta$llm_model, cfg$llm_model)) {
  stop("This round was drawn for annotator ", meta$llm_model, " but config.json now says ",
       cfg$llm_model, ". Draw a new round for the new model.", call. = FALSE)
}

prompt <- if (rerun) cfg$prompt else paste(readLines(file.path(rdir, "prompt.txt"), warn = FALSE), collapse = "\n")
suffix <- if (rerun) "_rerun" else ""
pairs  <- read.csv(file.path(rdir, "pairs.csv"))
comp   <- readRDS(file.path(run_dir, "comparisons.rds"))
comp   <- comp[match(pairs$pair_id, comp$pair_id), ]

out <- annotate(comp, cfg, prompt, cache = file.path(rdir, paste0("annotations", suffix, ".rds")))

n_na <- sum(is.na(out$winner))
if (n_na == nrow(out)) stop("Every request failed (all winners NA). Run check_keys.R --verify.", call. = FALSE)
if (n_na > 0) warning(n_na, " pair(s) came back with no answer.", call. = FALSE)

write.csv(data.frame(pair_id = out$pair_id, winner = out$winner),
          file.path(rdir, paste0("llm", suffix, ".csv")), row.names = FALSE)
if (rerun) writeLines(prompt, file.path(rdir, "prompt_rerun.txt"))
cat(sprintf("LLM judged %d of %d pairs in round '%s'%s.\n",
            nrow(out) - n_na, nrow(out), round, if (rerun) " (rerun with current prompt)" else ""))
