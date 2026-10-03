# Summarizes the evaluation JSONL files (MM-105) into the tables of
# docs/research/ai-evaluations.md: pass rate per provider and language, per
# feature, seconds per case and local tokens per second.
#   python3 scripts/evaluations/summarize.py docs/research/ai-evaluations/*.jsonl
import json, sys, statistics, collections

rows = [json.loads(line) for path in sys.argv[1:] for line in open(path)]

# Runs before the repeat check existed in AIEvaluationRunner are scored here
# with the same rule: a suggestion equal to a topic already in the map fails.
EXISTING = {
    "en": ["Healthy habits", "Sleep", "Fixed bedtime", "Exercise", "Nutrition", "Stress"],
    "vi": ["Du lịch Đà Nẵng 4 ngày", "Ẩm thực", "Mì Quảng", "Lịch trình", "Chi phí", "Khách sạn"],
    "ja": ["健康的な習慣", "睡眠", "決まった就寝時間", "運動", "食事", "ストレス"],
}
for r in rows:
    o = r["outcome"]
    if o["passed"] and o["feature"] in ("expandTopic", "brainstorm", "findMissingTopics"):
        existing = {t.lower() for t in EXISTING[o["language"]]}
        repeated = [t for t in o["output"].split(" | ") if t.lower() in existing]
        if repeated:
            o["passed"], o["reason"] = False, "repeats " + repeated[0]
providers = sorted({r["provider"] for r in rows}, key=lambda p: (p != "foundation-models", p))
languages = ["en", "vi", "ja"]
features = []
for r in rows:
    if r["outcome"]["feature"] not in features:
        features.append(r["outcome"]["feature"])

def cell(subset):
    passed = sum(r["outcome"]["passed"] for r in subset)
    return f"{passed}/{len(subset)}" if subset else "—"

print("| Provider | en | vi | ja | All | Median s/case | Tokens/s (end to end) |")
print("| --- | --- | --- | --- | --- | --- | --- |")
for p in providers:
    mine = [r for r in rows if r["provider"] == p]
    by_lang = [cell([r for r in mine if r["outcome"]["language"] == l]) for l in languages]
    seconds = statistics.median(r["outcome"]["seconds"] for r in mine)
    timed = [r for r in mine if r.get("completionTokens") and r.get("generationSeconds")]
    tps = (f"{sum(r['completionTokens'] for r in timed) / sum(r['generationSeconds'] for r in timed):.1f}" if timed else "—")
    print(f"| {p} | {' | '.join(by_lang)} | {cell(mine)} | {seconds:.1f} | {tps} |")

print()
print("| Feature | " + " | ".join(providers) + " |")
print("| --- |" + " --- |" * len(providers))
for f in features:
    cells = []
    for p in providers:
        subset = [r for r in rows if r["provider"] == p and r["outcome"]["feature"] == f]
        failed = [f"{r['outcome']['language']}: {r['outcome']['reason']}" for r in subset if not r["outcome"]["passed"]]
        cells.append(cell(subset) + (" (" + "; ".join(failed) + ")" if failed else ""))
    print(f"| {f} | " + " | ".join(cells) + " |")
