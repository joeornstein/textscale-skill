# textscale-skill

An [Agent Skill](https://agentskills.io) for Claude Code and other AI coding assistants. It helps your assistant measure a continuous concept (tone, ideology, grandstanding, smile size, anything you can compare) across a set of texts or images, using the [textscale](https://github.com/joeornstein/textscale) R package and the method in [Ornstein, "Scaling Documents with Pairwise Comparisons and Embeddings"](https://joeornstein.github.io/publications/textscale.pdf).

## Install

Ask your coding assistant:

> Install the textscale skill from https://github.com/joeornstein/textscale-skill

That's all. The first time you use the skill, it checks for R, the textscale package, Python and the API keys your chosen models need, and walks you through anything missing. (Instructions for the assistant are [below](#for-ai-coding-assistants).)

## What it does

Point your assistant at a folder of images, a folder of text files, or a CSV with a text column, and say what you want to measure: "Score these campaign ads by how negative they are." The skill then works through these steps with you:

1. **Setup.** You choose the annotator LLM and the embedding model. The defaults are textscale's: `gpt-5.4-mini`, `text-embedding-3-large` for text, and `gemini-embedding-2` for images. The skill confirms the API keys work.
2. **Calibration rounds.** You judge about 20 pairs of documents yourself in a local browser page, adding notes on the hard ones. Then you compare your answers with the LLM's. The disagreements are where a vague concept gets precise, and the assistant helps you turn them into a sharper comparison question.
3. **Audit round.** You judge about 100 fresh pairs blind, using the final question. Cohen's kappa between you and the LLM, with a bootstrap interval, is the reliability figure you can report.
4. **Full run.** Only after you approve a cost estimate does the LLM judge thousands of pairs. textscale then fits a ridge model on the document embeddings, validates it on held-out documents, and scores every document with a 95% interval.
5. **Zero point.** Scores are in log-odds units, like Bradley-Terry scores: a one-unit gap means the higher document wins about 73% of comparisons. The skill never rescales them. It does help you choose a meaningful zero (for example, documents you judge neutral) and check that documents near zero look neutral.

Everything ends up in a run folder next to your data:

- scores as a CSV
- every judging round with your answers and notes
- the validation results
- the fitted model, which can score new documents of the same kind without more comparisons

## Requirements

- **[R](https://www.r-project.org/) 4.3 or later, with textscale 0.0.0.9010 or later:** `pak::pak("joeornstein/textscale")`. The skill offers to install it.
- **Python 3:** for the local judging page. It uses only the standard library.
- **An OpenAI API key** for the annotator. Image embeddings need an [OpenRouter](https://openrouter.ai) key; text embeddings use OpenAI by default. The skill tells you which keys you need and how to store them in your `.Renviron`. Your keys never go through the chat.
- **An assistant that can run commands on your machine**, such as Claude Code. Cloud-only chats can't reach your files, R, or the judging page.

**Data.** Your documents are sent to the API providers you choose, OpenAI and possibly OpenRouter or Mistral, for annotation and embedding. Don't use the skill on data you aren't permitted to send to them.

**Cost.** The skill shows textscale's cost estimate and waits for your go-ahead before the full run. Text is usually cheap. Images cost more, about 1,500 input tokens per image per comparison. Halving the cost with OpenAI's Batch API is an option.

## For AI coding assistants

The user has asked you to install this skill. It adds instructions, reference notes and helper scripts (R and Python, run locally) for measuring documents with the textscale R package. Confirm with the user before installing if you normally would.

**Claude Code** (if the `claude` CLI is available):

```
claude plugin marketplace add joeornstein/textscale-skill
claude plugin install textscale@textscale-skill
```

Verify: `claude plugin list` shows `textscale@textscale-skill` as enabled. If the `claude` command isn't available to you, give the user these two commands to type in Claude Code: `/plugin marketplace add joeornstein/textscale-skill` and `/plugin install textscale@textscale-skill`.

**Other agents that support Agent Skills** (Codex and others): copy `skills/textscale/` from this repository into your skills directory (for Codex, `~/.agents/skills/`), so that `<skills dir>/textscale/SKILL.md` exists.

**Afterwards**, check that the skill is available in this session. In Claude Code it should appear in `/skills`. If it doesn't, run `/reload-plugins` (plugin install) or `/reload-skills` (manual copy), and restart the session only if that fails. In other agents, a new session may be needed. Then tell the user it's installed, and that the first time they ask to scale, rank or score documents, the skill will check their setup and walk them through anything missing.

Do not install R packages or set API keys as part of installing the skill. The skill handles setup when it runs, with the user present.

## Updating

For Claude Code plugin installs, run `claude plugin marketplace update textscale-skill`, then `claude plugin update textscale@textscale-skill`. Manual copies update by copying `skills/textscale/` again. Each [release](https://github.com/joeornstein/textscale-skill/releases) also has a `textscale.skill` file attached, which can be uploaded to Claude apps that support custom skills, wherever Claude has a shell on your machine.

## Citation

If you use this in research, please cite the paper (not this skill):

> Ornstein, Joseph T. "Scaling Documents with Pairwise Comparisons and Embeddings." Working paper. https://joeornstein.github.io/publications/textscale.pdf

## Development

- `skills/textscale/`: the skill (`SKILL.md`, `references/`, `scripts/`).
- `.claude-plugin/`: the plugin and marketplace manifests that make this repository installable in Claude Code.
- `tests/smoke_test.sh`: an end-to-end run of every script on synthetic texts and images, with the LLM and embedding APIs mocked (no keys, no cost). CI runs it on every push, and weekly against the current textscale on GitHub, so changes in the package that would break the skill show up here first.

To release, bump `version` in `.claude-plugin/plugin.json` and push a tag such as `v0.1.0`. The release workflow attaches `textscale.skill`.

## License

MIT. See [LICENSE.md](LICENSE.md).
