# Benchmarks small open models with MLX on the app's real prompts (MM-77).
# Research only: nothing here ships. Run with
#   uv run --python 3.12 --with mlx-lm scripts/research/local-llm-bench.py OUT.jsonl MODEL...
# Prompts mirror PromptCatalog (common rules + feature rules + rendered context);
# the JSON shape stands in for @Generable, which open runtimes do not have.
import json, os, sys, time, re
import mlx.core as mx
from mlx_lm import load, stream_generate
from mlx_lm.sample_utils import make_sampler

COMMON = """You help a person build a mind map: a tree of short topics around one central topic.
A topic title is a short phrase of at most eight words, not a sentence.
Keep names, technical terms and mixed Vietnamese and English wording exactly as the person wrote them.
Never repeat a topic that is already in the map."""

RULES = {
    "generateMap": "Create a mind map for the subject the person describes, with a short title.\nGive each topic a unique temporaryID such as t1, t2 and t3.\nA main topic has an empty parentTemporaryID; a subtopic names the temporaryID of its parent, listed before it.",
    "expandTopic": "Suggest subtopics that belong directly under the focus topic.",
    "brainstorm": "Brainstorm varied ideas related to the focus topic. Mix practical and unexpected ideas.",
    "rewrite": "Rewrite the title of the focus topic as asked. Keep its meaning.",
    "summarize": "Summarize the focus topic and its subtopics in plain sentences. Do not add facts that are not in the map.",
}
SCHEMA = {
    "generateMap": '{"title": string, "topics": [{"temporaryID": string, "parentTemporaryID": string, "title": string}]}',
    "expandTopic": '{"topics": [{"title": string}]}',
    "brainstorm": '{"topics": [{"title": string}]}',
    "rewrite": '{"titles": [string]}',
    "summarize": '{"summary": string}',
}
CASES = [
    ("generateMap", "en", "Subject: Launch plan for a mobile budgeting app\nCreate a mind map with at most 20 topics and at most three levels."),
    ("generateMap", "vi", "Subject: Kế hoạch ôn thi tốt nghiệp THPT môn Toán trong 3 tháng\nCreate a mind map with at most 20 topics and at most three levels."),
    ("expandTopic", "en", "Map: Healthy habits\nFocus topic: Sleep\nExisting subtopics:\n- Fixed bedtime\nTopics beside the focus topic: Exercise; Nutrition; Stress\nSuggest up to 6 new subtopics for the focus topic."),
    ("expandTopic", "vi", "Map: Du lịch Đà Nẵng 4 ngày\nPath to the focus topic: Du lịch Đà Nẵng 4 ngày\nFocus topic: Ẩm thực\nExisting subtopics:\n- Mì Quảng\nTopics beside the focus topic: Lịch trình; Chi phí; Khách sạn\nSuggest up to 6 new subtopics for the focus topic."),
    ("brainstorm", "en", "Map: Team offsite\nFocus topic: Team-building activities\nBrainstorm up to 8 ideas around the focus topic."),
    ("brainstorm", "vi", "Map: Cửa hàng cà phê nhỏ\nFocus topic: Tăng khách quen\nBrainstorm up to 8 ideas around the focus topic."),
    ("rewrite", "en", "Map: Q4 roadmap\nFocus topic: we should probably look into making the onboarding flow faster for new users\nGive up to 3 alternative titles for the focus topic. Make it shorter."),
    ("rewrite", "vi", "Map: Kế hoạch dự án HIS\nFocus topic: cần phải xem lại cái backend architecture vì nó chạy chậm quá khi nhiều user\nGive up to 3 alternative titles for the focus topic. Make it clearer."),
    ("summarize", "en", "Map: Home renovation\nFocus topic: Kitchen\nExisting subtopics:\n- Budget: 12,000 USD\n- New cabinets\n  - Oak, matte finish\n- Move the sink under the window\n- Contractor: start in March\nSummarize this branch in two to four sentences."),
    ("summarize", "vi", "Map: Khởi nghiệp\nFocus topic: Gọi vốn vòng hạt giống\nExisting subtopics:\n- Mục tiêu 500.000 USD\n- Nhà đầu tư thiên thần\n  - Anh Minh (đã gặp)\n- Pitch deck 12 trang\n- Hạn chót: tháng 6\nSummarize this branch in two to four sentences."),
]
LANG = {"en": "English", "vi": "Vietnamese"}
VI_MARKS = re.compile(r"[ăâđêôơưàáảãạằắẳẵặầấẩẫậèéẻẽẹềếểễệìíỉĩịòóỏõọồốổỗộờớởỡợùúủũụừứửữựỳýỷỹỵ]", re.I)

def messages(feature, lang, prompt):
    system = "\n".join([COMMON, RULES[feature], "The person's locale is " + ("vi_VN" if lang == "vi" else "en_US") + ".",
                        "You MUST respond in " + LANG[lang] + ".",
                        "Answer with JSON only, no Markdown, matching: " + SCHEMA[feature]])
    return [{"role": "system", "content": system}, {"role": "user", "content": prompt}]

def parse(text):
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.S).strip()
    text = re.sub(r"^```(?:json)?|```$", "", text.strip(), flags=re.M).strip()
    try:
        return json.loads(text), True
    except Exception:
        m = re.search(r"\{.*\}", text, re.S)
        if m:
            try:
                return json.loads(m.group(0)), False
            except Exception:
                pass
    return None, False

def run(model_id, out):
    t0 = time.time()
    model, tok = load(model_id)
    load_s = time.time() - t0
    sampler = make_sampler(temp=0.3)
    only = os.environ.get("ONLY")  # e.g. ONLY=generateMap MAX_TOKENS=1500 to rerun the long answers
    for feature, lang, prompt in CASES:
        if only and feature != only:
            continue
        kwargs = {"add_generation_prompt": True, "tokenize": False}
        if "Qwen3" in model_id:
            kwargs["enable_thinking"] = False  # thinking doubles latency for no gain on short JSON
        try:
            text_in = tok.apply_chat_template(messages(feature, lang, prompt), **kwargs)
        except Exception:  # templates without a system role (Gemma 2 era) get it folded into the user turn
            m = messages(feature, lang, prompt)
            text_in = tok.apply_chat_template([{"role": "user", "content": m[0]["content"] + "\n\n" + m[1]["content"]}], **kwargs)
        mx.reset_peak_memory()
        text, last, first_at = "", None, None
        start = time.time()
        for r in stream_generate(model, tok, text_in, max_tokens=int(os.environ.get("MAX_TOKENS", "700")), sampler=sampler):
            if first_at is None:
                first_at = time.time() - start
            text += r.text
            last = r
        obj, strict = parse(text)
        rec = {"model": model_id, "feature": feature, "lang": lang, "load_s": round(load_s, 1),
               "ttft_s": round(first_at or 0, 2), "total_s": round(time.time() - start, 2),
               "prompt_tps": round(last.prompt_tps, 1), "gen_tps": round(last.generation_tps, 1),
               "gen_tokens": last.generation_tokens, "peak_gb": round(mx.get_peak_memory() / 1e9, 2),
               "json_strict": strict, "json_ok": obj is not None,
               "vi_marks": bool(VI_MARKS.search(text)), "output": text}
        out.write(json.dumps(rec, ensure_ascii=False) + "\n"); out.flush()
        print(model_id, feature, lang, rec["gen_tps"], "tok/s", rec["peak_gb"], "GB", "json", rec["json_ok"], flush=True)
    del model

if __name__ == "__main__":
    with open(sys.argv[1], "a") as out:
        for model_id in sys.argv[2:]:
            try:
                run(model_id, out)
            except Exception as e:
                print("FAILED", model_id, repr(e), flush=True)
    print("BENCH DONE", flush=True)
