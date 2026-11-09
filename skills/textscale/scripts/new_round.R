# Draw a fresh set of pairs for the user to judge.
# Usage: Rscript new_round.R <run_dir> <round_name> <n_pairs> <calibration|audit>
#
# Pairs come from the comparison design (so they look like what the model
# is trained on) and never repeat a pair used in an earlier round, so an
# audit round is genuinely held out from the pairs used to tune the prompt.
# Snapshots the current prompt from config.json into the round.

source(file.path(dirname(normalizePath(sub("--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "common.R"))

a <- commandArgs(trailingOnly = TRUE)
if (length(a) < 4 || !a[4] %in% c("calibration", "audit")) {
  stop("Usage: Rscript new_round.R <run_dir> <round_name> <n_pairs> <calibration|audit>", call. = FALSE)
}
run_dir <- args_run_dir(); round <- a[2]; n <- as.integer(a[3]); kind <- a[4]
if (!grepl("^[A-Za-z0-9_-]+$", round)) stop("Round names may use letters, digits, - and _ only.", call. = FALSE)

cfg  <- read_config(run_dir)
comp <- readRDS(file.path(run_dir, "comparisons.rds"))
rdir <- round_dir(run_dir, round)
if (dir.exists(rdir)) stop("Round '", round, "' already exists.", call. = FALSE)

pair_key <- function(x, y) paste(pmin(x, y), pmax(x, y))
used <- character()
for (r in list_rounds(run_dir)$round) {
  p <- read.csv(file.path(round_dir(run_dir, r), "pairs.csv"))
  used <- c(used, pair_key(p$doc_id_a, p$doc_id_b))
}
avail <- comp[!pair_key(comp$doc_id_a, comp$doc_id_b) %in% used, ]
if (nrow(avail) == 0) stop("No unused pairs left in the design.", call. = FALSE)
if (n > nrow(avail)) { message("Only ", nrow(avail), " unused pairs left; using all."); n <- nrow(avail) }

set.seed(cfg$seed + 1000L + length(used))
pick <- avail[sample(nrow(avail), n), ]

dir.create(rdir, recursive = TRUE)
write.csv(data.frame(pair_id = pick$pair_id, doc_id_a = pick$doc_id_a, doc_id_b = pick$doc_id_b),
          file.path(rdir, "pairs.csv"), row.names = FALSE)
writeLines(cfg$prompt, file.path(rdir, "prompt.txt"))
jsonlite::write_json(list(
  kind = kind, n = n, created = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  llm_model = cfg$llm_model, allow_ties = isTRUE(cfg$allow_ties), prompt = cfg$prompt
), file.path(rdir, "meta.json"), auto_unbox = TRUE, pretty = TRUE)

cat(sprintf("Round '%s' (%s): %d pairs (%d train / %d test split). Prompt:\n  %s\n",
            round, kind, n, sum(pick$split == "train"), sum(pick$split == "test"), cfg$prompt))
