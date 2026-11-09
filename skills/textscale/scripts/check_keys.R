# Check that the API keys the chosen models need are visible to R, and say
# where R is reading them from. Never prints a key.
# Usage: Rscript check_keys.R <run_dir> [--verify]
#   --verify  also makes one free, read-only request per provider (list
#             models / key info) to confirm each key is accepted.
#
# Exit status 0 when every needed key is present (and accepted, with
# --verify); 1 otherwise.
#
# Run this from the same working directory you will run the other scripts
# from: R reads ./.Renviron in the working directory INSTEAD of
# ~/.Renviron when one exists.

source(file.path(dirname(normalizePath(sub("--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "common.R"))

run_dir <- args_run_dir()
verify  <- "--verify" %in% commandArgs(trailingOnly = TRUE)
cfg     <- read_config(run_dir)
keys    <- required_keys(cfg)

# Which user environment file did this R session read?
renv_file <- local({
  env_set <- Sys.getenv("R_ENVIRON_USER")
  if (nzchar(env_set)) return(path.expand(env_set))
  if (file.exists(".Renviron")) return(normalizePath(".Renviron"))
  path.expand("~/.Renviron")
})
renv_lines <- if (file.exists(renv_file)) readLines(renv_file, warn = FALSE) else character()

cat(sprintf("Annotator: %s | Embeddings (%s): %s\n", cfg$llm_model, cfg$document_type, cfg$embedding_model))
cat(sprintf("R reads user environment variables from: %s%s\n", renv_file,
            if (file.exists(renv_file)) "" else " (file does not exist)"))
if (file.exists(".Renviron") && !nzchar(Sys.getenv("R_ENVIRON_USER"))) {
  cat("NOTE: a .Renviron in the current working directory is shadowing ~/.Renviron.\n")
}

endpoints <- c(
  OPENAI_API_KEY     = "https://api.openai.com/v1/models",
  OPENROUTER_API_KEY = "https://openrouter.ai/api/v1/key",
  MISTRAL_API_KEY    = "https://api.mistral.ai/v1/models"
)

ok <- TRUE
for (k in keys) {
  val <- Sys.getenv(k)
  in_file <- any(grepl(paste0("^\\s*", k, "\\s*="), renv_lines))
  where <- if (!nzchar(val)) "MISSING" else if (in_file) paste("set in", basename(renv_file)) else "set (from the shell environment, not the .Renviron file)"
  status <- ""
  if (nzchar(val) && verify) {
    resp <- tryCatch(
      httr2::req_perform(httr2::req_error(
        httr2::req_timeout(httr2::req_auth_bearer_token(httr2::request(endpoints[[k]]), val), 20),
        is_error = function(r) FALSE)),
      error = function(e) NULL)
    code <- if (is.null(resp)) NA else httr2::resp_status(resp)
    status <- if (is.na(code)) " | could not reach provider" else if (code == 200) " | accepted" else
      sprintf(" | REJECTED (HTTP %d)", code)
    if (is.na(code) || code != 200) ok <- FALSE
  }
  if (!nzchar(val)) ok <- FALSE
  cat(sprintf("%-19s %s%s\n", k, where, status))
}
quit(status = if (ok) 0 else 1)
