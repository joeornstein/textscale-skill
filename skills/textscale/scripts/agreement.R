# Human vs. LLM agreement for one round.
# Usage: Rscript agreement.R <run_dir> <round> [--rerun]
#
# Writes report.md (or report_rerun.md) and disagreements.csv
# (disagreements_rerun.csv) in the round folder and prints the report.
#
# Primary statistic: Cohen's kappa with A / B / tie as nominal categories,
# with a percentile bootstrap CI over pairs. Secondary: kappa on pairs
# where both judges made a decisive call (ties are dropped before fitting,
# so that subset is what trains the scale). Pairs the user skipped are
# excluded from both and counted.

source(file.path(dirname(normalizePath(sub("--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "common.R"))

a       <- commandArgs(trailingOnly = TRUE)
run_dir <- args_run_dir(); round <- a[2]; rerun <- "--rerun" %in% a
suffix  <- if (rerun) "_rerun" else ""
rdir    <- round_dir(run_dir, round)
meta    <- jsonlite::read_json(file.path(rdir, "meta.json"), simplifyVector = TRUE)
docs    <- load_run_documents(run_dir)
cfg     <- read_config(run_dir)
B       <- 2000L

pairs <- read.csv(file.path(rdir, "pairs.csv"))
human <- read_human(rdir); names(human)[2] <- "human"
llm   <- read.csv(file.path(rdir, paste0("llm", suffix, ".csv")), stringsAsFactors = FALSE)
names(llm)[2] <- "llm"

d <- merge(merge(pairs, human, by = "pair_id"), llm, by = "pair_id", all.x = TRUE)
n_skip   <- sum(d$human == "skip")
n_llm_na <- sum(!d$llm %in% c("A", "B", "tie"))
d <- d[d$human %in% c("A", "B", "tie") & d$llm %in% c("A", "B", "tie"), ]
d$agree <- d$human == d$llm

kappa <- function(x, y, levels) {
  tab <- table(factor(x, levels), factor(y, levels)) / length(x)
  po <- sum(diag(tab)); pe <- sum(rowSums(tab) * colSums(tab))
  if (isTRUE(all.equal(pe, 1))) return(NA_real_)  # no variation: undefined
  (po - pe) / (1 - pe)
}
boot_kappa <- function(x, y, levels) {
  est <- if (length(x)) kappa(x, y, levels) else NA_real_
  if (length(x) < 2 || is.na(est)) return(c(est = est, lower = NA, upper = NA))
  set.seed(1L)
  reps <- replicate(B, { i <- sample(length(x), replace = TRUE); kappa(x[i], y[i], levels) })
  ci <- quantile(reps, c(.025, .975), na.rm = TRUE)
  c(est = est, lower = unname(ci[1]), upper = unname(ci[2]))
}
fmt <- function(k) if (is.na(k["est"])) "undefined (no variation or no pairs)" else
  sprintf("%.2f [%.2f, %.2f]", k["est"], k["lower"], k["upper"])

lv  <- c("A", "B", "tie")
k3  <- boot_kappa(d$human, d$llm, lv)
dec <- d[d$human != "tie" & d$llm != "tie", ]
k2  <- boot_kappa(dec$human, dec$llm, c("A", "B"))
conf <- table(factor(d$human, lv), factor(d$llm, lv))

# Disagreements, with the user's notes, for the conversation that follows.
show <- function(id) if (cfg$document_type == "image") docs$content[id] else snippet(docs$content[id], 300)
dis <- merge(merge(pairs, human, by = "pair_id"), llm, by = "pair_id", all.x = TRUE)
dis <- dis[is.na(dis$llm) | dis$human != dis$llm | dis$human == "skip" | nzchar(dis$note), ]
write.csv(data.frame(
  pair_id = dis$pair_id, human = dis$human, llm = dis$llm, note = dis$note,
  label_a = docs$label[dis$doc_id_a], label_b = docs$label[dis$doc_id_b],
  doc_a = show(dis$doc_id_a), doc_b = show(dis$doc_id_b)
), file.path(rdir, paste0("disagreements", suffix, ".csv")), row.names = FALSE, fileEncoding = "UTF-8")

prompt_used <- paste(readLines(file.path(rdir, if (rerun) "prompt_rerun.txt" else "prompt.txt"), warn = FALSE), collapse = " ")
header <- if (meta$kind == "audit" && !rerun) {
  "Held-out audit round: this is the reliability estimate for the prompt below."
} else if (rerun) {
  "DIAGNOSTIC rerun with the revised prompt on pairs that informed the revision; agreement here is optimistic and is not a reliability estimate."
} else {
  "Calibration round: exploratory. The prompt may be revised in light of these pairs, so this is not a reliability estimate."
}
report <- c(
  sprintf("# Round '%s' (%s): human vs. LLM", round, meta$kind), "", header, "",
  sprintf("Prompt: %s", prompt_used), "",
  sprintf("- Pairs compared: %d of %d (%d skipped by the user; %d LLM answers missing or invalid)",
          nrow(d), nrow(pairs), n_skip, n_llm_na),
  sprintf("- **Cohen's kappa (A / B / tie): %s**  (95%% percentile bootstrap, %d resamples over pairs)", fmt(k3), B),
  sprintf("- Raw agreement: %d / %d (%.0f%%)", sum(d$agree), nrow(d), if (nrow(d)) 100 * mean(d$agree) else NaN),
  sprintf("- Kappa on decisive pairs only (neither judge said tie, n = %d): %s", nrow(dec), fmt(k2)),
  sprintf("- Ties: human %d, LLM %d", sum(d$human == "tie"), sum(d$llm == "tie")),
  sprintf("- Chose the first-listed item (A): human %.0f%%, LLM %.0f%% of decisive answers",
          100 * mean(d$human[d$human != "tie"] == "A"), 100 * mean(d$llm[d$llm != "tie"] == "A")),
  "", "## Confusion matrix (rows: human, columns: LLM)", "",
  "| | A | B | tie |", "|---|---|---|---|",
  sprintf("| %s | %d | %d | %d |", lv, conf[, "A"], conf[, "B"], conf[, "tie"]), "",
  sprintf("Disagreements, skips and every pair with a note: disagreements%s.csv", suffix)
)
writeLines(report, file.path(rdir, paste0("report", suffix, ".md")))
cat(report, sep = "\n")
