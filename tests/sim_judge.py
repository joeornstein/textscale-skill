#!/usr/bin/env python3
"""Simulated human judge for the smoke test: answers every pair in a round
through the judging server's HTTP API, the same way the browser page does.

Usage: python3 sim_judge.py PORT RUN_DIR ROUND TRUTH_CSV
"""
import csv
import json
import math
import random
import sys
import time
import urllib.request

csv.field_size_limit(sys.maxsize)
port, run_dir, rnd, truth_csv = sys.argv[1:5]
base = f"http://127.0.0.1:{port}"
random.seed(11)

for _ in range(100):  # wait for the server to come up
    try:
        state = json.load(urllib.request.urlopen(base + "/api/state", timeout=2))
        break
    except Exception:
        time.sleep(0.1)
else:
    sys.exit("judging server did not start")

truth = {r["key"]: float(r["latent"]) for r in csv.DictReader(open(truth_csv, encoding="utf-8"))}
docs = {}
for r in csv.DictReader(open(f"{run_dir}/documents.csv", encoding="utf-8")):
    docs[r["doc_id"]] = truth[r["text"]] if "text" in r else truth[r["path"].split("/")[-1]]
pairs = {r["pair_id"]: (r["doc_id_a"], r["doc_id_b"]) for r in csv.DictReader(open(f"{run_dir}/rounds/{rnd}/pairs.csv"))}

for pid in state["pair_ids"]:
    a, b = pairs[pid]
    d = docs[a] - docs[b]
    note = ""
    if state["allow_ties"] and abs(d) < 0.05:
        w, note = "tie", "about the same"
    else:
        w = "A" if random.random() < 1 / (1 + math.exp(-6 * d)) else "B"
        if abs(d) < 0.15:
            note = "close call"
    if random.random() < 0.04:
        w, note = "skip", "not comparable"
    body = json.dumps({"pair_id": pid, "winner": w, "note": note}).encode()
    urllib.request.urlopen(urllib.request.Request(base + "/api/judge", body, {"Content-Type": "application/json"}))

after = json.load(urllib.request.urlopen(base + "/api/state"))
print(f"simulated judge answered {len(after['judged'])}/{len(after['pair_ids'])} pairs in round {rnd}")
