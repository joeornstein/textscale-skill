# Shared helpers for the textscale skill scripts. Sourced by the others.
# Every script takes the run directory as its first argument.

suppressPackageStartupMessages(library(jsonlite))

# textscale's print/plot methods use `%||%`, which is base R only from 4.4.0.
# On older R the operator is found here instead (namespace lookup falls
# through to the global environment), so validation output still prints.
if (!exists("%||%", baseenv())) `%||%` <- function(x, y) if (is.null(x)) y else x

IMAGE_EXT <- c("jpg", "jpeg", "png", "webp", "gif")
TEXT_EXT  <- c("txt", "md")

DEFAULTS <- list(
  document_type        = NULL,      # "text" or "image"; inferred from `input` if missing
  text_column          = "text",    # CSV input only
  id_column            = NULL,      # CSV input only; row number if NULL
  block_column         = NULL,      # compare only within blocks (CSV column, or metadata_csv column)
  metadata_csv         = NULL,      # folder input only: CSV with a `file` column plus block_column
  allow_ties           = TRUE,
  llm_model            = "gpt-5.4-mini",
  embedding_model      = NULL,      # NULL = package default for the document type
  embedding_dimensions = 256L,      # OpenAI text-embedding-3-* only
  resize               = "high",    # image detail sent to the annotator and embedder
  n_train              = 10000L,
  n_test               = 5000L,
  prop                 = 0.8,
  seed                 = 42L,
  use_batch            = FALSE,     # OpenAI Batch API for the full run: half price, can take hours
  force                = FALSE      # accept a model that fails validation (user's decision only)
)

default_embedding_model <- function(type) {
  if (type == "image") "google/gemini-embedding-2" else "text-embedding-3-large"
}

script_dir <- function() {
  f <- sub("--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  dirname(normalizePath(f))
}

args_run_dir <- function() {
  a <- commandArgs(trailingOnly = TRUE)
  if (length(a) < 1) stop("Usage: Rscript <script> <run_dir> [...]", call. = FALSE)
  normalizePath(a[1], mustWork = TRUE)
}

infer_type <- function(input) {
  if (!dir.exists(input)) return("text")  # a CSV of texts
  ext <- tolower(tools::file_ext(list.files(input)))
  n_img <- sum(ext %in% IMAGE_EXT); n_txt <- sum(ext %in% TEXT_EXT)
  if (n_img == 0 && n_txt == 0) stop("No images or .txt/.md files found in ", input, call. = FALSE)
  if (n_img > 0 && n_txt > 0) {
    stop("The folder has both images and text files; set document_type in config.json.", call. = FALSE)
  }
  if (n_img > 0) "image" else "text"
}

read_config <- function(run_dir) {
  path <- file.path(run_dir, "config.json")
  if (!file.exists(path)) stop("No config.json in ", run_dir, call. = FALSE)
  cfg <- jsonlite::read_json(path, simplifyVector = TRUE)
  for (k in names(DEFAULTS)) if (is.null(cfg[[k]])) cfg[k] <- list(DEFAULTS[[k]])
  for (k in c("input", "prompt")) {
    if (is.null(cfg[[k]]) || !nzchar(cfg[[k]])) stop("config.json needs `", k, "`.", call. = FALSE)
  }
  cfg$input <- normalizePath(cfg$input, mustWork = TRUE)
  if (is.null(cfg$document_type)) cfg$document_type <- infer_type(cfg$input)
  if (!cfg$document_type %in% c("text", "image")) stop("document_type must be 'text' or 'image'.", call. = FALSE)
  if (is.null(cfg$embedding_model)) cfg$embedding_model <- default_embedding_model(cfg$document_type)
  cfg
}

# Which API keys the chosen models need. textscale's annotator calls OpenAI
# directly; image embeddings go through OpenRouter; text embeddings go
# through fuzzylink, which routes "org/model" names to OpenRouter.
required_keys <- function(cfg) {
  emb <- if (cfg$document_type == "image" || grepl("/", cfg$embedding_model)) {
    "OPENROUTER_API_KEY"
  } else if (cfg$embedding_model == "mistral-embed") {
    "MISTRAL_API_KEY"
  } else {
    "OPENAI_API_KEY"
  }
  unique(c(annotator = "OPENAI_API_KEY", embeddings = emb))
}

# Documents as a data frame: doc_id (1..n, the index textscale uses), label
# (file name or id; never shown to the judge), content (the text itself, or
# an absolute image path, which is what textscale takes), and block.
load_documents <- function(cfg) {
  inp <- cfg$input
  if (dir.exists(inp)) {
    ext   <- if (cfg$document_type == "image") IMAGE_EXT else TEXT_EXT
    files <- list.files(inp, full.names = TRUE)
    files <- sort(normalizePath(files[tolower(tools::file_ext(files)) %in% ext]))
    content <- if (cfg$document_type == "image") files else
      vapply(files, function(f) paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n"), "")
    docs <- data.frame(label = basename(files), content = unname(content), stringsAsFactors = FALSE)
    docs$block <- NA_character_
    if (!is.null(cfg$metadata_csv)) {
      meta <- read.csv(cfg$metadata_csv, stringsAsFactors = FALSE, check.names = FALSE)
      if (is.null(cfg$block_column) || !all(c("file", cfg$block_column) %in% names(meta))) {
        stop("metadata_csv needs a `file` column and the block_column named in config.json.", call. = FALSE)
      }
      docs$block <- as.character(meta[[cfg$block_column]][match(docs$label, meta$file)])
    }
  } else {
    if (cfg$document_type == "image") stop("Image input must be a folder.", call. = FALSE)
    d <- read.csv(inp, stringsAsFactors = FALSE, check.names = FALSE, encoding = "UTF-8")
    if (!cfg$text_column %in% names(d)) {
      stop("Column `", cfg$text_column, "` not found. Columns: ", paste(names(d), collapse = ", "), call. = FALSE)
    }
    ids <- if (is.null(cfg$id_column)) as.character(seq_len(nrow(d))) else as.character(d[[cfg$id_column]])
    docs <- data.frame(label = ids, content = as.character(d[[cfg$text_column]]), stringsAsFactors = FALSE)
    docs$block <- if (is.null(cfg$block_column)) NA_character_ else as.character(d[[cfg$block_column]])
  }

  empty <- is.na(docs$content) | !nzchar(trimws(docs$content))
  if (any(empty)) {
    message("Dropping ", sum(empty), " empty document(s): ", paste(head(docs$label[empty], 10), collapse = ", "))
    docs <- docs[!empty, ]
  }
  if (!is.null(cfg$block_column) && any(is.na(docs$block))) {
    stop(sum(is.na(docs$block)), " document(s) have no value in block column `", cfg$block_column, "`.", call. = FALSE)
  }
  # textscale keys embeddings and the annotation cache by document content,
  # so identical documents would silently collapse into one.
  dup <- duplicated(docs$content) | duplicated(docs$content, fromLast = TRUE)
  if (any(dup)) {
    stop("Some documents are identical (", paste(head(docs$label[dup], 10), collapse = ", "),
         "). Remove or merge duplicates first.", call. = FALSE)
  }
  docs$doc_id <- seq_len(nrow(docs))
  docs[, c("doc_id", "label", "content", "block")]
}

load_run_documents <- function(run_dir) readRDS(file.path(run_dir, "documents.rds"))

# The system prompt textscale will build, reproduced for cost estimates.
system_prompt_for <- function(cfg, prompt) {
  sp <- if (isTRUE(cfg$allow_ties)) "Respond with 'A', 'B', or 'tie'." else
    "Respond with a single letter ('A' or 'B') only. No ties allowed."
  if (cfg$document_type == "image") {
    sp <- paste0("You will be shown two images, labelled Image A and Image B, in that order.\n", sp)
  }
  paste0(prompt, "\n", sp)
}

# The one call to annotate_comparisons() used everywhere. textscale's cache
# hash covers the prompt but NOT the model, so callers must never point two
# different annotator models at the same cache file.
annotate <- function(comparisons, cfg, prompt, cache, batch = FALSE) {
  textscale::annotate_comparisons(
    comparisons,
    instructions  = prompt,
    model         = cfg$llm_model,
    document_type = cfg$document_type,
    resize        = cfg$resize,
    allow_ties    = isTRUE(cfg$allow_ties),
    cache         = cache,
    parallel      = !batch,
    path          = file.path(dirname(cache), "batch_checkpoint.json")
  )
}

# Which rows of `comparisons` a cache file would answer for this prompt,
# reproducing textscale's own hash check (so estimates match what happens).
cache_hits <- function(cache, comparisons, cfg, prompt) {
  if (!file.exists(cache)) return(rep(FALSE, nrow(comparisons)))
  cached <- readRDS(cache)
  sp <- system_prompt_for(cfg, prompt)
  hash <- if (cfg$document_type == "image") textscale:::.prompt_hash("image", cfg$resize, sp) else
    textscale:::.prompt_hash("A: {{text_a}}\nB: {{text_b}}", sp)
  if (!identical(attr(cached, "prompt_hash"), hash)) return(rep(FALSE, nrow(comparisons)))
  key <- function(d) paste(d$text_a, d$text_b, sep = "\t")
  w <- cached$winner[match(key(comparisons), key(cached))]
  !is.na(w)
}

main_cache <- function(run_dir, cfg) {
  file.path(run_dir, sprintf("annotations_%s.rds", gsub("[^A-Za-z0-9]+", "-", cfg$llm_model)))
}

# The most recent audit round, and whether it still matches config.json.
latest_audit <- function(run_dir, cfg) {
  r <- list_rounds(run_dir)
  if (!nrow(r)) return(NULL)
  r <- r[r$kind == "audit", ]
  if (!nrow(r)) return(NULL)
  name <- r$round[nrow(r)]
  rdir <- round_dir(run_dir, name)
  meta <- jsonlite::read_json(file.path(rdir, "meta.json"), simplifyVector = TRUE)
  list(round = name, dir = rdir, meta = meta,
       matches = identical(meta$prompt, cfg$prompt) && identical(meta$llm_model, cfg$llm_model) &&
         identical(isTRUE(meta$allow_ties), isTRUE(cfg$allow_ties)))
}

embed <- function(docs, cfg, run_dir) {
  extra <- list()
  if (cfg$document_type == "text" && grepl("^text-embedding-3", cfg$embedding_model)) {
    extra$dimensions <- as.integer(cfg$embedding_dimensions)
  }
  if (cfg$document_type == "image") extra$resize <- cfg$resize
  do.call(textscale::get_embeddings, c(list(
    docs$content,
    cache = file.path(run_dir, sprintf("embeddings_%s.rds", gsub("[^A-Za-z0-9]+", "-", cfg$embedding_model))),
    type  = cfg$document_type,
    model = cfg$embedding_model
  ), extra))
}

# ---- rounds ------------------------------------------------------------------

round_dir <- function(run_dir, round) file.path(run_dir, "rounds", round)

list_rounds <- function(run_dir) {
  dirs <- list.dirs(file.path(run_dir, "rounds"), recursive = FALSE)
  if (length(dirs) == 0) return(data.frame())
  meta <- lapply(dirs, function(d) {
    m <- jsonlite::read_json(file.path(d, "meta.json"), simplifyVector = TRUE)
    data.frame(round = basename(d), kind = m$kind, created = m$created,
               llm_model = m$llm_model, stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, meta)
  out[order(out$created), ]
}

read_human <- function(rdir) {
  f <- file.path(rdir, "human.csv")
  if (!file.exists(f)) return(data.frame(pair_id = integer(), winner = character(), note = character()))
  h <- read.csv(f, stringsAsFactors = FALSE, na.strings = character(0))
  h <- h[!duplicated(h$pair_id, fromLast = TRUE), ]  # the last answer per pair counts
  h[, c("pair_id", "winner", "note")]
}

snippet <- function(x, n = 160) {
  x <- gsub("\\s+", " ", x)
  ifelse(nchar(x) > n, paste0(substr(x, 1, n - 3), "..."), x)
}
