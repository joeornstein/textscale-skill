#!/usr/bin/env bash
# End-to-end smoke test of every skill script, on synthetic texts and images,
# with the LLM and embedding APIs mocked (tests/mock_profile.R). No API keys
# or network needed beyond installing packages. Needs R with textscale,
# python3, and curl.
#
# Usage: bash tests/smoke_test.sh   (from the repository root)

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/skills/textscale/scripts"
W="$ROOT/tests/work"
rm -rf "$W"; mkdir -p "$W"

export R_PROFILE_USER="$ROOT/tests/mock_profile.R"
export TRUTH_CSV="$W/truth.csv"
export OPENAI_API_KEY=test-not-a-key OPENROUTER_API_KEY=test-not-a-key

PIDS=()
cleanup() { for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

step() { printf '\n== %s\n' "$*"; }
fail() { printf '\nFAIL: %s\n' "$*" >&2; exit 1; }

judge_round() {  # run_dir round port
  python3 "$S/judge_server.py" --run-dir "$1" --round "$2" --port "$3" > "$W/server_$2_$3.log" 2>&1 &
  local pid=$!; PIDS+=("$pid")
  python3 "$ROOT/tests/sim_judge.py" "$3" "$1" "$2" "$TRUTH_CSV"
  kill "$pid"
}

set_prompt() {  # run_dir new_prompt
  python3 - "$1/config.json" "$2" <<'EOF'
import json, sys
p, prompt = sys.argv[1], sys.argv[2]
c = json.load(open(p)); c["prompt"] = prompt
json.dump(c, open(p, "w"), indent=2)
EOF
}

check_scores() {  # scores.csv min_correlation
  python3 - "$1" "$TRUTH_CSV" "$2" <<'EOF'
import csv, statistics, sys
csv.field_size_limit(sys.maxsize)
scores, truth_csv, min_r = sys.argv[1], sys.argv[2], float(sys.argv[3])
t = {r["key"]: float(r["latent"]) for r in csv.DictReader(open(truth_csv, encoding="utf-8"))}
rows = list(csv.DictReader(open(scores, encoding="utf-8")))
key = (lambda r: r["text"]) if "text" in rows[0] else (lambda r: r["path"].split("/")[-1])
r = statistics.correlation([float(x["score"]) for x in rows], [t[key(x)] for x in rows])
assert all(float(x["lower"]) <= float(x["score"]) <= float(x["upper"]) for x in rows), "score outside its interval"
print(f"{len(rows)} documents scored; correlation with true latent = {r:.3f}")
sys.exit(0 if r >= min_r else 1)
EOF
}

step "fixtures"
Rscript "$ROOT/tests/make_fixtures.R" "$W"
Rscript -e 'cat("textscale", as.character(packageVersion("textscale")), "\n")'

# ---------------------------------------------------------------- text ------
T="$W/texts/run"; mkdir -p "$T"
cat > "$T/config.json" <<EOF
{"input": "$W/texts/statements.csv", "text_column": "text", "id_column": "speech_id",
 "block_column": "committee", "prompt": "Which statement is a clearer case of grandstanding?",
 "n_train": 1500, "n_test": 400, "seed": 42}
EOF

step "text: keys"
Rscript "$S/check_keys.R" "$T"
( unset OPENAI_API_KEY; ! Rscript "$S/check_keys.R" "$T" > /dev/null ) || fail "check_keys passed with a missing key"

step "text: prepare and calibration round"
Rscript "$S/prepare.R" "$T"
Rscript "$S/new_round.R" "$T" cal1 20 calibration
Rscript "$S/round_llm.R" "$T" cal1
judge_round "$T" cal1 8761
Rscript "$S/agreement.R" "$T" cal1 > /dev/null
[ -s "$T/rounds/cal1/disagreements.csv" ] || fail "no disagreements.csv"

step "text: revise prompt, diagnostic rerun"
set_prompt "$T" "Which statement is a clearer case of grandstanding?
Definition: count direct attacks on a person or institution; ignore procedural length."
Rscript "$S/round_llm.R" "$T" cal1 --rerun
Rscript "$S/agreement.R" "$T" cal1 --rerun > "$W/out.txt"; grep -q DIAGNOSTIC "$W/out.txt" || fail "rerun report not labeled diagnostic"

step "text: full run refuses before an audit"
if Rscript "$S/run_full.R" "$T" > /dev/null 2>&1; then fail "run_full ran without an audit round"; fi

step "text: audit round"
Rscript "$S/new_round.R" "$T" audit 80 audit
Rscript "$S/round_llm.R" "$T" audit
judge_round "$T" audit 8762
Rscript "$S/agreement.R" "$T" audit > "$W/out.txt"; grep -q "Held-out audit round" "$W/out.txt" || fail "audit report header"
python3 - "$T" <<'EOF' || fail "rounds reused a pair"
import csv, sys
seen = set()
for r in ("cal1", "audit"):
    for p in csv.DictReader(open(f"{sys.argv[1]}/rounds/{r}/pairs.csv")):
        k = frozenset((p["doc_id_a"], p["doc_id_b"]))
        assert k not in seen; seen.add(k)
EOF

step "text: cost estimate reuses annotations made under the final prompt"
Rscript "$S/estimate_cost.R" "$T" | tee "$W/cost.txt"
# 80 audit pairs + the 20 calibration pairs re-judged under the final prompt
grep -q "(100 already cached)" "$W/cost.txt" || fail "audit and rerun pairs not counted as cached"

step "text: full run"
Rscript "$S/run_full.R" "$T"
for f in scores.csv comparisons.csv validation.txt calibration.png result.rds; do [ -s "$T/$f" ] || fail "missing $f"; done
check_scores "$T/scores.csv" 0.8 || fail "text scores do not recover the latent ordering"

step "text: recenter"
Rscript "$S/recenter.R" "$T" --preview --show 5 > /dev/null
Rscript "$S/recenter.R" "$T" --ref-docs 3,7 --show 3
python3 - "$T/scores_centered.csv" <<'EOF' || fail "recentering changed the spacing or missed the anchor"
import csv, sys
csv.field_size_limit(sys.maxsize)
rows = list(csv.DictReader(open(sys.argv[1], encoding="utf-8")))
shift = {round(float(r["score_raw"]) - float(r["score"]), 9) for r in rows}
assert len(shift) == 1, shift
anchor = [float(r["score"]) for r in rows if r["doc_id"] in ("3", "7")]
assert abs(sum(anchor) / 2) < 1e-9, anchor
EOF
Rscript "$S/recenter.R" "$T" --median --show 3 > /dev/null

step "text: a different annotator model gets nothing from the cache"
python3 - "$T/config.json" <<'EOF'
import json, sys
p = sys.argv[1]; c = json.load(open(p)); c["llm_model"] = "gpt-5.4"; json.dump(c, open(p, "w"), indent=2)
EOF
Rscript "$S/estimate_cost.R" "$T" > "$W/out.txt"; grep -q "(0 already cached)" "$W/out.txt" || fail "cache reused across annotator models"
python3 - "$T/config.json" <<'EOF'
import json, sys
p = sys.argv[1]; c = json.load(open(p)); c["llm_model"] = "gpt-5.4-mini"; json.dump(c, open(p, "w"), indent=2)
EOF
Rscript "$S/estimate_cost.R" "$T" > "$W/out.txt"; grep -q "Pairs to annotate: 0 " "$W/out.txt" || fail "switching back did not reuse the original model's answers"

step "text: prompt drift after the audit is refused"
set_prompt "$T" "Which statement is more negative?"
if Rscript "$S/run_full.R" "$T" > /dev/null 2>&1; then fail "run_full ran with an unaudited prompt"; fi

# ---------------------------------------------------------------- images ----
I="$W/images_run"; mkdir -p "$I"
cat > "$I/config.json" <<EOF
{"input": "$W/images", "prompt": "Which image looks brighter and busier?",
 "allow_ties": false, "n_train": 700, "n_test": 200, "seed": 42}
EOF

step "images: prepare and audit round"
Rscript "$S/check_keys.R" "$I"
Rscript "$S/prepare.R" "$I"
Rscript "$S/new_round.R" "$I" audit 50 audit
python3 "$S/judge_server.py" --run-dir "$I" --round audit --port 8763 > "$W/server_img.log" 2>&1 &
SP=$!; PIDS+=("$SP")
for _ in $(seq 1 50); do curl -s -o /dev/null http://127.0.0.1:8763/api/state && break; sleep 0.1; done
PID1=$(sed -n 2p "$I/rounds/audit/pairs.csv" | cut -d, -f1)
[ "$(curl -s -o /dev/null -w '%{http_code} %{content_type}' "http://127.0.0.1:8763/img/$PID1/a")" = "200 image/png" ] || fail "image not served"
[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST -d "{\"pair_id\":\"$PID1\",\"winner\":\"tie\"}" http://127.0.0.1:8763/api/judge)" = "400" ] || fail "tie accepted with ties off"
kill "$SP"
judge_round "$I" audit 8764
Rscript "$S/round_llm.R" "$I" audit
Rscript "$S/agreement.R" "$I" audit > /dev/null

step "images: full run"
Rscript "$S/run_full.R" "$I"
check_scores "$I/scores.csv" 0.8 || fail "image scores do not recover the latent ordering"

printf '\nAll smoke tests passed.\n'
