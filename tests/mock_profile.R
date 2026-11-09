# Test double for the network: loaded via R_PROFILE_USER by smoke_test.sh.
# When textscale loads, its internal wrappers around the OpenAI chat and the
# embedding endpoints are replaced with offline fakes driven by a known
# latent value per document (TRUTH_CSV). Everything else, including
# textscale's prompt hashing and annotation cache, runs for real.

setHook(packageEvent("textscale", "onLoad"), function(...) {
  truth <- utils::read.csv(Sys.getenv("TRUTH_CSV"), stringsAsFactors = FALSE)
  latent <- function(x) {
    key <- ifelse(file.exists(x), basename(x), x)
    v <- truth$latent[match(key, truth$key)]
    if (anyNA(v)) stop("mock: unknown document ", x[is.na(v)][1])
    v
  }

  fake_embeddings <- function(documents, ...) {
    set.seed(7)
    m <- matrix(stats::rnorm(length(documents) * 32, sd = 0.3), ncol = 32)
    m[, 1] <- 3 * latent(documents) + stats::rnorm(length(documents), sd = 0.2)
    rownames(m) <- documents
    m
  }

  fake_chat <- function(system_prompt = NULL, model = NULL, ...) {
    list(system_prompt = system_prompt, model = model)
  }

  # A noisy judge: P(A) = logistic(k * (latent_A - latent_B)), with a small
  # first-position bias, and sharper when the prompt carries a definition.
  fake_parallel <- function(chat, prompts, ...) {
    ties  <- grepl("'tie'", chat$system_prompt)
    sharp <- if (grepl("Definition", chat$system_prompt)) 14 else 7
    vapply(prompts, function(p) {
      if (is.list(p)) {
        d <- latent(p[[2]]$path) - latent(p[[4]]$path)
      } else {
        ab <- regmatches(as.character(p), regexec("^A: (.*)\nB: (.*)$", as.character(p)))[[1]]
        d <- latent(ab[2]) - latent(ab[3])
      }
      if (ties && abs(d) < 0.03) return("tie")
      if (stats::runif(1) < stats::plogis(sharp * d + 0.1)) "A" else "B"
    }, character(1), USE.NAMES = FALSE)
  }

  ns <- asNamespace("textscale")
  fakes <- list(
    .chat_openai            = fake_chat,
    .parallel_chat_text     = fake_parallel,
    .batch_chat_text        = function(chat, prompts, path = NULL, ...) fake_parallel(chat, prompts),
    .content_image_file     = function(path, ...) list(path = path),
    .fetch_embeddings       = fake_embeddings,
    .fetch_image_embeddings = fake_embeddings
  )
  for (nm in names(fakes)) {
    if (!exists(nm, envir = ns, inherits = FALSE)) stop("mock: textscale no longer has ", nm, "; update tests/mock_profile.R")
    unlockBinding(nm, ns)
    assign(nm, fakes[[nm]], envir = ns)
  }
})
