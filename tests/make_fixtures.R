# Synthetic documents with known latent values, for the smoke test.
# Usage: Rscript make_fixtures.R <work_dir>
# Writes <work_dir>/texts/statements.csv, <work_dir>/images/*.png and
# <work_dir>/truth.csv (key = text or image file name, latent in [0, 1]).

work <- commandArgs(trailingOnly = TRUE)[1]
dir.create(file.path(work, "texts"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(work, "images"), recursive = TRUE, showWarnings = FALSE)
set.seed(5)

openers <- c("The committee met on Tuesday.", "Members reviewed the budget.", "The witness described the program.",
             "Staff summarized the findings.", "The chair opened the session.", "A report was circulated.")
mild <- c("This is somewhat concerning.", "I have a few questions about that.", "We should look into this further.")
hot  <- c("This is an absolute disgrace!", "You should be ashamed of yourself.", "Frankly, this is outrageous.",
          "How dare you mislead this committee?", "This administration has failed the American people.")

n_txt <- 80
v_txt <- runif(n_txt)
texts <- vapply(seq_len(n_txt), function(i) {
  parts <- c(sample(openers, 1), if (v_txt[i] < 0.5) sample(mild, 1),
             sample(hot, round(v_txt[i] * 4)), rep("Further procedural details were noted.", sample(0:3, 1)))
  sprintf("%s (Item %d.)", paste(parts, collapse = " "), i)
}, "")
write.csv(data.frame(speech_id = sprintf("s%03d", seq_len(n_txt)),
                     committee = sample(c("Judiciary", "Oversight"), n_txt, replace = TRUE),
                     text = texts),
          file.path(work, "texts", "statements.csv"), row.names = FALSE)

n_img <- 40
v_img <- runif(n_img)
files <- sprintf("photo_%04d.png", sample(1000:9999, n_img))
for (i in seq_len(n_img)) {
  grDevices::png(file.path(work, "images", files[i]), width = 320, height = 240)
  graphics::par(mar = c(0, 0, 0, 0), bg = grDevices::gray(0.15 + 0.8 * v_img[i]))
  graphics::plot.new()
  k <- 3 + round(12 * v_img[i])
  graphics::symbols(runif(k), runif(k), circles = rep(0.04, k), inches = FALSE, add = TRUE, fg = "#c8502a", lwd = 3)
  grDevices::dev.off()
}

write.csv(data.frame(key = c(texts, files), latent = c(v_txt, v_img)),
          file.path(work, "truth.csv"), row.names = FALSE)
cat(sprintf("Fixtures: %d texts, %d images in %s\n", n_txt, n_img, work))
