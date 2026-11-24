"""Render a bench/run.py JSON report as Markdown. Every number comes from the
JSON; nothing is computed by hand (ADR-0010).

    python -m bench.report bench/reports/<stamp>-ledger.json
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def render(report: dict) -> str:
    env, verdicts, runs = report["environment"], report["verdicts"], report["runs"]
    by_id = {v["id"]: v for v in verdicts}
    base = runs[0]["summary"]
    out = ["# Ledger API: optimisation claims, checked then measured", ""]
    out += [f"Measured {env['measured_at']}; **expires {env['expires']}** (re-measure after that).", ""]
    out += ["## Verdicts on meaning (before any timing)", "",
            "| Claim | Kind | Verdict | Why |", "|---|---|---|---|"]
    for v in verdicts:
        why = "; ".join(r["code"] for r in v["reasons"]) or "no guarantee lost; conforms to the spec"
        comp = v["evidence"].get("compensations") or []
        if v["verdict"] == "accept" and comp:
            why = "drops `" + "`, `".join(v["declared_drops"]) + "`, compensated by Lean proof " + \
                  ", ".join(f"`{c['statement']}`" for c in comp)
        out.append(f"| {v['id']} | {v['kind']} | **{v['verdict']}** | {why} |")
    out += ["", "## Speed, over HTTP", "",
            f"Median of {env['load']['reps']} runs of {env['load']['seconds']:g} s, {env['load']['threads']} "
            f"keep-alive clients, {env['data']['parties']} parties × {env['data']['bills_per_party']} seeded bills.", "",
            "| Configuration | Verdict | req/s | × baseline | p50 ms | p95 ms | p99 ms | errors |",
            "|---|---|---|---|---|---|---|---|"]
    for r in runs:
        s, label = r["summary"], r["label"]
        verdict = "—" if label == "baseline" else ("accepted set" if label == "ALL-ACCEPTED"
                                                     else by_id[label]["verdict"])
        out.append(f"| {label} | {verdict} | {s['throughput_rps']} | {s['speedup_vs_baseline']} | "
                   f"{s['p50_ms']} | {s['p95_ms']} | {s['p99_ms']} | {s['errors']} |")
    out += ["", "Rejected claims are measured only to show what speed was on offer. They are not in "
            "`ALL-ACCEPTED`.", "", "### By operation (p99 ms)", "",
            "| Configuration | " + " | ".join(base["by_op"]) + " |",
            "|---|" + "---|" * len(base["by_op"])]
    for r in runs:
        out.append(f"| {r['label']} | " + " | ".join(str(r["summary"]["by_op"][op]["p99_ms"])
                                                       for op in base["by_op"]) + " |")
    out += ["", "## Counterexamples found", ""]
    for v in verdicts:
        ce = v["evidence"]["conformance"].get("shrunk_counterexample")
        if ce:
            out += [f"**{v['id']}**: {len(ce['ops'])} operations; at the last one the spec says",
                    f"`{json.dumps(ce['model'])}`", "", "but the store says", f"`{json.dumps(ce['store'])}`", ""]
        for r in v["reasons"]:
            if r["code"] == "undeclared_drop":
                out += [f"**{v['id']}**: drops `{', '.join(r['detail']['guarantees'])}` without declaring it, "
                        f"which breaks {', '.join(r['detail']['breaks_rules'])}. Observed pragmas: "
                        f"`{json.dumps(v['evidence']['observed']['candidate']['pragmas'])}`.", ""]
    out += ["## Where the baseline spends its time (cProfile, top by own time)", "", "```",
            report["profile_baseline"].strip(), "```", "", "## Environment", "", "```json",
            json.dumps(env, indent=2), "```", ""]
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    path = Path((argv or sys.argv[1:])[0])
    md = path.with_suffix(".md")
    md.write_text(render(json.loads(path.read_text(encoding="utf-8"))), encoding="utf-8", newline="\n")
    print(f"wrote {md}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
