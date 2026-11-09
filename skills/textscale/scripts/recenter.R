# Move the zero point of the scale. Never changes the spacing: differences
# between scores, and their log-odds meaning, are untouched.
# Usage:
#   Rscript recenter.R <run_dir> --ref-docs 12,40,77   # zero = mean of these documents (doc_id)
#   Rscript recenter.R <run_dir> --ref-labels a.jpg,b.jpg
#   Rscript recenter.R <run_dir> --value 1.3           # zero = this raw score
#   Rscript recenter.R <run_dir> --median              # zero = corpus median (descriptive, not "neutral")
#   Rscript recenter.R <run_dir> --preview [--show 12] # no change; documents spread across the scale
# Add --show N to change how many documents near zero are listed (default 10).
#
# With reference documents, a recentered score is x_i'b - mean(x_ref)'b =
# (x_i - mean(x_ref))'b, so textscale's Laplace intervals are recomputed on
# the shifted embeddings and include the uncertainty in where the reference
# sits. A reference document then reads as "log-odds of being chosen over
# the reference". With --value or --median the shift is a constant and the
# intervals simply move with it (uncertainty in the anchor is not included).
#
# Writes scores_centered.csv (score, lower, upper, score_raw) and
# anchor.json; scores.csv is left as it was.

source(file.path(dirname(normalizePath(sub("--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "common.R"))

a       <- commandArgs(trailingOnly = TRUE)
run_dir <- args_run_dir()
cfg     <- read_config(run_dir)
res     <- readRDS(file.path(run_dir, "result.rds"))
docs    <- res$docs
emb     <- res$embeddings
opt     <- function(flag) { i <- match(flag, a); if (is.na(i)) NULL else a[i + 1] }
show_n  <- if (is.null(opt("--show"))) 10L else as.integer(opt("--show"))

raw <- textscale::score_documents(res$model_final, emb, ci = TRUE, ci_method = "laplace")
describe <- function(ids, sc) {
  txt <- if (cfg$document_type == "image") docs$content[ids] else snippet(docs$content[ids])
  sprintf("  %7.2f [%6.2f, %6.2f]  #%-5d %-24s %s", sc$score[ids], sc$lower[ids], sc$upper[ids],
          docs$doc_id[ids], substr(docs$label[ids], 1, 24), txt)
}

if ("--preview" %in% a) {
  # A spread of documents at evenly spaced quantiles, to help the user say
  # where "neutral" falls before choosing an anchor.
  q <- unique(round(quantile(seq_len(nrow(docs)), seq(0, 1, length.out = show_n))))
  ids <- order(raw$score)[q]
  cat("Raw scores across the scale (low to high):\n", paste(describe(ids, raw), collapse = "\n"), "\n", sep = "")
  quit(status = 0)
}

ref_ids <- NULL
if (!is.null(opt("--ref-docs"))) ref_ids <- as.integer(strsplit(opt("--ref-docs"), ",")[[1]])
if (!is.null(opt("--ref-labels"))) {
  labs <- trimws(strsplit(opt("--ref-labels"), ",")[[1]])
  ref_ids <- match(labs, docs$label)
  if (anyNA(ref_ids)) stop("Unknown label(s): ", paste(labs[is.na(ref_ids)], collapse = ", "), call. = FALSE)
}

if (!is.null(ref_ids)) {
  if (any(!ref_ids %in% docs$doc_id)) stop("Unknown doc_id(s).", call. = FALSE)
  shift <- colMeans(emb[ref_ids, , drop = FALSE])
  sc <- textscale::score_documents(res$model_final, sweep(emb, 2, shift), ci = TRUE, ci_method = "laplace")
  anchor <- list(type = "reference documents", doc_id = ref_ids, label = docs$label[ref_ids],
                 raw_offset = mean(raw$score[ref_ids]))
} else {
  v <- if ("--median" %in% a) median(raw$score) else if (!is.null(opt("--value"))) as.numeric(opt("--value")) else
    stop("Give --ref-docs, --ref-labels, --value, --median or --preview.", call. = FALSE)
  sc <- data.frame(score = raw$score - v, lower = raw$lower - v, upper = raw$upper - v)
  anchor <- list(type = if ("--median" %in% a) "corpus median" else "fixed value", raw_offset = v)
}

out <- data.frame(doc_id = docs$doc_id, label = docs$label, score = sc$score, lower = sc$lower,
                  upper = sc$upper, score_raw = raw$score)
if (!is.null(cfg$block_column)) out$block <- docs$block
if (cfg$document_type == "image") out$path <- docs$content else out$text <- docs$content
write.csv(out[order(-out$score), ], file.path(run_dir, "scores_centered.csv"), row.names = FALSE, fileEncoding = "UTF-8")
jsonlite::write_json(anchor, file.path(run_dir, "anchor.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)

cat(sprintf("Zero = %s (raw score %.3f). Spacing unchanged.\n", anchor$type, anchor$raw_offset))
if (!is.null(ref_ids)) cat("Reference documents now score:\n", paste(describe(ref_ids, sc), collapse = "\n"), "\n", sep = "")
near <- order(abs(sc$score))[seq_len(min(show_n, nrow(docs)))]
cat(sprintf("\n%d documents nearest the new zero (these should look neutral):\n", length(near)),
    paste(describe(near, sc), collapse = "\n"), "\n", sep = "")
cat(sprintf("\nShare of documents above zero: %.0f%%\n", 100 * mean(sc$score > 0)))
