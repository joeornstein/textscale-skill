# Load the documents, fix their order, and generate the comparison design
# that both the judging rounds and the full run draw from.
# Usage: Rscript prepare.R <run_dir>
#
# Writes: documents.rds (full table), documents.csv (what the judging page
# reads), comparisons.rds (the design, with pair_id).
#
# Safe to re-run with a different design size: rounds store document ids,
# not pair ids, so earlier rounds stay valid. Not safe to re-run after the
# input documents change (doc_ids would shift); start a new run instead.

source(file.path(dirname(normalizePath(sub("--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "common.R"))

run_dir <- args_run_dir()
cfg     <- read_config(run_dir)
docs    <- load_documents(cfg)

old <- file.path(run_dir, "documents.rds")
if (file.exists(old) && !identical(readRDS(old)$content, docs$content)) {
  stop("The input documents differ from those this run was prepared with. Start a new run directory.", call. = FALSE)
}
if (nrow(docs) < 10) stop("Only ", nrow(docs), " documents; need at least 10 for an 80/20 split.", call. = FALSE)

saveRDS(docs, file.path(run_dir, "documents.rds"))
csv <- data.frame(doc_id = docs$doc_id, label = docs$label, block = docs$block)
if (cfg$document_type == "image") csv$path <- docs$content else csv$text <- docs$content
write.csv(csv, file.path(run_dir, "documents.csv"), row.names = FALSE, fileEncoding = "UTF-8")

blocks <- if (is.null(cfg$block_column)) NULL else docs$block
comparisons <- textscale::generate_comparisons(
  docs$content, n_train = cfg$n_train, n_test = cfg$n_test, prop = cfg$prop,
  blocks = blocks, seed = cfg$seed
)
comparisons$pair_id <- seq_len(nrow(comparisons))
saveRDS(comparisons, file.path(run_dir, "comparisons.rds"))

cat(sprintf("Documents: %d %s\n", nrow(docs), cfg$document_type))
if (cfg$document_type == "text") {
  n <- nchar(docs$content)
  cat(sprintf("Length (characters): median %d, max %d\n", as.integer(median(n)), max(n)))
}
if (!is.null(blocks)) cat(sprintf("Blocks (`%s`): %d; pairs are drawn within blocks only\n",
                                  cfg$block_column, length(unique(blocks))))
cat(sprintf("Design: %d train + %d test pairs (%.0f/%.0f document split, seed %d)\n",
            sum(comparisons$split == "train"), sum(comparisons$split == "test"),
            100 * cfg$prop, 100 * (1 - cfg$prop), cfg$seed))
