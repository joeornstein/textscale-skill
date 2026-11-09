#!/usr/bin/env python3
"""Local judging page for one textscale round (text or images).

Shows one pair at a time with the round's comparison question and saves
each answer the moment it is given. Standard library only; binds to
127.0.0.1 so the documents are never exposed to the network.

Usage:
  python3 judge_server.py --run-dir RUN --round ROUND [--port 8765] [--open]

Reads RUN/config.json, RUN/documents.csv, RUN/rounds/ROUND/{pairs.csv,
prompt.txt, meta.json}. Appends to RUN/rounds/ROUND/human.csv with columns
pair_id, winner (A | B | tie | skip), note, judged_at. A pair answered more
than once keeps every row; the last one counts. Document labels (file names,
ids) are never sent to the page, so they cannot cue the judgment.
"""

import argparse
import csv
import json
import mimetypes
import os
import sys
import threading
import webbrowser
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PAGE = Path(__file__).resolve().parent / "judge_page.html"
csv.field_size_limit(sys.maxsize)


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def load_judged(path):
    judged = {}
    if os.path.isfile(path):
        for r in read_csv(path):
            judged[str(r["pair_id"])] = {"winner": r["winner"], "note": r.get("note", "")}
    return judged


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--round", required=True)
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--open", action="store_true", help="open the page in the default browser")
    args = ap.parse_args()

    run = Path(args.run_dir).resolve()
    rdir = run / "rounds" / args.round
    cfg = json.loads((run / "config.json").read_text(encoding="utf-8"))
    meta = json.loads((rdir / "meta.json").read_text(encoding="utf-8"))
    prompt = (rdir / "prompt.txt").read_text(encoding="utf-8").strip()
    allow_ties = bool(meta.get("allow_ties", cfg.get("allow_ties", True)))
    out_path = rdir / "human.csv"

    docs = {r["doc_id"]: r for r in read_csv(run / "documents.csv")}
    doc_type = "image" if "path" in next(iter(docs.values())) else "text"
    pairs = {r["pair_id"]: (r["doc_id_a"], r["doc_id_b"]) for r in read_csv(rdir / "pairs.csv")}
    order = [r["pair_id"] for r in read_csv(rdir / "pairs.csv")]
    for a, b in pairs.values():
        for d in (a, b):
            if d not in docs:
                sys.exit(f"Document {d} is in pairs.csv but not documents.csv")
            if doc_type == "image" and not os.path.isfile(docs[d]["path"]):
                sys.exit(f"Image not found: {docs[d]['path']}")

    lock = threading.Lock()
    valid = {"A", "B", "skip"} | ({"tie"} if allow_ties else set())

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _send(self, code, body, ctype="application/json"):
            if isinstance(body, (dict, list)):
                body = json.dumps(body).encode()
            elif isinstance(body, str):
                body = body.encode()
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            p = self.path.split("?")[0]
            if p in ("/", "/index.html"):
                return self._send(200, PAGE.read_bytes(), "text/html; charset=utf-8")
            if p == "/api/state":
                with lock:
                    judged = load_judged(out_path)
                return self._send(200, {
                    "prompt": prompt, "allow_ties": allow_ties, "type": doc_type,
                    "kind": meta.get("kind", "calibration"), "round": args.round,
                    "pair_ids": order, "judged": {k: v for k, v in judged.items() if k in pairs},
                })
            parts = p.strip("/").split("/")
            if len(parts) == 3 and parts[0] == "api" and parts[1] == "pair" and parts[2] in pairs:
                a, b = pairs[parts[2]]
                if doc_type == "text":
                    return self._send(200, {"a": docs[a]["text"], "b": docs[b]["text"]})
                return self._send(200, {"a": f"/img/{parts[2]}/a", "b": f"/img/{parts[2]}/b"})
            if len(parts) == 3 and parts[0] == "img" and parts[1] in pairs and parts[2] in ("a", "b"):
                if doc_type == "image":
                    fp = docs[pairs[parts[1]][0 if parts[2] == "a" else 1]]["path"]
                    ctype = mimetypes.guess_type(fp)[0] or "application/octet-stream"
                    return self._send(200, Path(fp).read_bytes(), ctype)
            return self._send(404, {"error": "not found"})

        def do_POST(self):
            if self.path != "/api/judge":
                return self._send(404, {"error": "not found"})
            try:
                data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
                pid, winner = str(data["pair_id"]), data["winner"]
                note = str(data.get("note", ""))[:4000]
            except Exception:
                return self._send(400, {"error": "bad request"})
            if pid not in pairs or winner not in valid:
                return self._send(400, {"error": "unknown pair or invalid answer"})
            with lock:
                new = not out_path.exists()
                with open(out_path, "a", newline="", encoding="utf-8") as f:
                    w = csv.writer(f)
                    if new:
                        w.writerow(["pair_id", "winner", "note", "judged_at"])
                    w.writerow([pid, winner, note, datetime.now(timezone.utc).isoformat()])
                    f.flush()
                    os.fsync(f.fileno())
            return self._send(200, {"ok": True})

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://127.0.0.1:{args.port}/"
    print(f"Judging page for round '{args.round}': {url}  "
          f"({len(load_judged(out_path))}/{len(order)} pairs already answered)", flush=True)
    if args.open:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
