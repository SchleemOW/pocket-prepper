#!/usr/bin/env python3
"""
Pocket Prepper - LLM Evaluation (works with plain blob database format)
"""

import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import yaml, json, re, struct, time, logging, requests
from pathlib import Path
from datetime import datetime

logging.getLogger("sentence_transformers").setLevel(logging.ERROR)
logging.getLogger("huggingface_hub").setLevel(logging.ERROR)

DB_DIR = Path(__file__).parent.parent / "data" / "databases"
RESULTS_DIR = Path(__file__).parent / "results"
RESULTS_DIR.mkdir(exist_ok=True)

OLLAMA_URL = "http://localhost:11434/api/generate"
EVAL_MODEL = "gemma2:2b"
TOP_K = 15

SYNONYMS = {
    "filter": ["filter", "filtering", "filtration", "strain", "straining", "sieve"],
    "boil": ["boil", "boiling", "boiled"],
    "cloth": ["cloth", "fabric", "clothing", "shirt", "bandana", "rag"],
    "distill": ["distill", "distillation", "distilling", "evaporate", "evaporation"],
    "condense": ["condense", "condensation", "condensing", "collect steam"],
    "clean": ["clean", "cleaning", "cleanliness", "wash", "washing", "sanitize"],
    "trap": ["trap", "trapping", "traps", "snare", "snaring", "deadfall"],
    "snare": ["snare", "snaring", "trap", "trapping", "noose", "loop"],
    "hunt": ["hunt", "hunting", "hunted", "track", "stalk"],
    "bark": ["bark", "cambium", "inner bark", "tree bark"],
    "cricket": ["cricket", "grasshopper", "insect", "grub", "worm", "larvae"],
    "milky sap": ["milky sap", "milky or discolored sap", "milky", "discolored sap"],
    "star": ["star", "stars", "celestial", "polaris", "north star", "constellation"],
    "compass": ["compass", "direction", "bearing", "magnetic"],
    "council": ["council", "committee", "assembly", "representatives", "elected"],
    "consensus": ["consensus", "agreement", "majority", "vote", "democratic"],
    "oral": ["oral", "verbal", "spoken", "storytelling", "word of mouth"],
    "apprentice": ["apprentice", "apprenticeship", "mentor", "hands-on", "learn by doing"],
    "gradual": ["gradual", "gradually", "slowly", "slow", "gentle", "gently"],
    "ice fishing": ["ice fishing", "fishing through ice", "frozen", "ice hole"],
    "coal": ["coal", "coals", "ember", "embers", "charcoal"],
    "friction": ["friction", "rubbing", "rub"],
    "bow drill": ["bow drill", "bow-drill", "bow and drill", "fire bow"],
    "smoke": ["smoke", "smoking", "smoked", "smoky"],
    "mirror": ["mirror", "reflection", "reflective", "signal mirror", "shiny"],
    "signal": ["signal", "signaling", "signalling", "attract attention"],
    "plan": ["plan", "planning", "strategy", "prioritize", "think"],
    "priorities": ["priorities", "priority", "prioritize", "most important", "first"],
    "calm": ["calm", "calming", "relax", "composure", "panic", "stress", "fear"],
    "hole": ["hole", "pit", "dig", "excavation", "depression"],
    "condensation": ["condensation", "condense", "moisture", "droplets", "dew"],
    "sun": ["sun", "solar", "sunlight", "sunshine"],
    "shade": ["shade", "shadow", "shelter", "cover", "protected"],
    "insulation": ["insulation", "insulate", "insulating", "warmth", "heat retention", "thermal"],
    "leaves": ["leaves", "leaf", "foliage", "debris", "vegetation"],
    "branches": ["branches", "branch", "bough", "limbs", "sticks"],
    "pressure": ["pressure", "press", "pressing", "direct pressure", "compress"],
    "elevate": ["elevate", "elevation", "raise", "raised", "above"],
    "tourniquet": ["tourniquet", "tight band", "constrict"],
    "splint": ["splint", "splinting", "immobilize", "rigid"],
    "cool": ["cool", "cooling", "cold water", "cold"],
    "bandage": ["bandage", "dressing", "wrap", "cloth", "cover"],
    "honey": ["honey"],
    "garlic": ["garlic"],
    "salt": ["salt", "salted", "salting", "sodium"],
    "sugar": ["sugar", "glucose", "sweet"],
    "rehydration": ["rehydration", "rehydrate", "oral rehydration", "ORS", "fluid"],
    "ferment": ["ferment", "fermentation", "fermenting", "fermented"],
    "lye": ["lye", "alkali", "caustic", "potash"],
    "fat": ["fat", "grease", "tallow", "lard", "oil", "animal fat"],
    "ash": ["ash", "ashes", "wood ash"],
    "wire": ["wire", "wiring", "conductor", "copper wire"],
    "coil": ["coil", "winding", "wound", "inductor"],
    "antenna": ["antenna", "aerial", "dipole"],
    "crystal": ["crystal", "diode", "detector", "galena"],
    "generator": ["generator", "dynamo", "alternator"],
    "turbine": ["turbine", "wheel", "runner", "impeller"],
    "bellows": ["bellows", "blower", "air supply", "forced air"],
    "furnace": ["furnace", "forge", "kiln", "smelter", "bloomery"],
    "charcoal": ["charcoal", "char", "carbonized wood"],
    "clay": ["clay", "mud", "earth"],
    "container": ["container", "vessel", "pot", "bucket", "bottle", "jar"],
    "dig": ["dig", "digging", "excavate", "hole"],
    "rain": ["rain", "rainfall", "rainwater", "precipitation"],
    "tinder": ["tinder", "kindling", "fire starter", "dry material"],
    "shelter": ["shelter", "cover", "protection", "lean-to", "debris hut"],
    "fire": ["fire", "flame", "burn", "ignite"],
    "water": ["water", "hydration", "drink", "fluid"],
    "exposure": ["exposure", "hypothermia", "cold", "heat", "elements"],
    "cord": ["cord", "umbilical", "tie", "string"],
    "sterile": ["sterile", "clean", "sanitize", "disinfect", "boil"],
    "position": ["position", "positioning", "squat", "lying", "sitting"],
    "massage": ["massage", "rub", "rubbing", "knead"],
    "uterus": ["uterus", "womb", "belly", "abdomen", "fundus"],
    "breastfeed": ["breastfeed", "breastfeeding", "nurse", "nursing"],
    "airway": ["airway", "airways", "mouth", "nose", "clear the mouth"],
    "stimulate": ["stimulate", "stimulation", "rub the back", "flick"],
    "vote": ["vote", "voting", "ballot", "election", "democratic"],
    "rules": ["rules", "rule", "law", "regulation", "agreement", "charter"],
    "mediation": ["mediation", "mediator", "neutral party", "arbitration"],
    "exchange": ["exchange", "trade", "barter", "swap"],
    "spear": ["spear", "spearing", "gig", "sharp stick", "prong"],
    "net": ["net", "netting", "seine", "mesh"],
    "weir": ["weir", "dam", "fish trap", "channel"],
    "bait": ["bait", "lure", "attract"],
    "store": ["storage", "storing", "stored", "preserve", "keep"],
    "stored": ["stored", "storage", "stockpile", "cache", "reserve", "preserved"],
}


def load_embedder():
    from sentence_transformers import SentenceTransformer
    return SentenceTransformer("all-MiniLM-L6-v2")


def retrieve(module_id, question, embedder, top_k=TOP_K):
    try:
        from pysqlite3 import dbapi2 as sqlite3
    except ImportError:
        import sqlite3

    db_path = DB_DIR / f"{module_id}.db"
    if not db_path.exists():
        return []

    query_vec = embedder.encode([question], normalize_embeddings=True)[0]
    conn = sqlite3.connect(str(db_path))

    results = []
    try:
        for row in conn.execute("SELECT id, text, title, source, embedding FROM chunks WHERE embedding IS NOT NULL"):
            rid, text, title, source, emb_blob = row
            if emb_blob is None:
                continue
            emb = list(struct.iter_unpack('f', emb_blob))
            vec = [x[0] for x in emb]
            dot = sum(a * b for a, b in zip(query_vec, vec))
            nA = sum(a * a for a in query_vec) ** 0.5
            nB = sum(b * b for b in vec) ** 0.5
            dist = 1.0 - (dot / (nA * nB)) if nA * nB > 0 else 2.0
            results.append((dist, text, title, source))
    except Exception as e:
        print(f"Retrieve error: {e}")

    conn.close()
    results.sort(key=lambda x: x[0])
    return [{"text": r[1], "title": r[2], "source": r[3], "distance": r[0]} for r in results[:top_k]]


def ask_ollama(question, context, scenario_context):
    system = (
        "You are a practical survival expert. "
        "Answer using ONLY the provided context. "
        "Be specific and actionable. Never suggest calling emergency services, "
        "going to a hospital, or buying anything — all infrastructure is destroyed. "
        f"SITUATION: {scenario_context}"
    )
    prompt = f"CONTEXT:\n{context}\n\nQUESTION: {question}\n\nANSWER:"
    try:
        resp = requests.post(OLLAMA_URL, json={
            "model": EVAL_MODEL, "system": system, "prompt": prompt, "stream": False,
        }, timeout=120)
        return resp.json().get("response", "")
    except Exception as e:
        return f"[ERROR: {e}]"


AMBIGUOUS_FORBIDDEN = {
    "store": [r'\b(go to|visit|find|the|a) store\b', r'\bgrocery store\b', r'\bhardware store\b'],
    "doctor": [r'\b(see|call|visit|consult|find) (a |the )?doctor\b'],
    "hospital": [r'\b(go to|visit|take .* to|nearest|the|a) hospital\b'],
}

def check_forbidden(answer_lower, concept):
    cl = concept.lower()
    if cl in AMBIGUOUS_FORBIDDEN:
        return any(re.search(p, answer_lower) for p in AMBIGUOUS_FORBIDDEN[cl])
    return bool(re.search(r'\b' + re.escape(cl) + r'\b', answer_lower))

def check_required(text_lower, concept):
    cl = concept.lower()
    if cl in SYNONYMS:
        return any(s.lower() in text_lower for s in SYNONYMS[cl])
    return bool(re.search(r'\b' + re.escape(cl) + r'\b', text_lower))

def score_answer(answer, required, forbidden):
    al = answer.lower()
    r = {"required_hits": [], "required_misses": [], "forbidden_hits": [],
         "required_score": 0, "forbidden_score": 0, "total_score": 0}
    for c in required:
        (r["required_hits"] if check_required(al, c) else r["required_misses"]).append(c)
    for c in forbidden:
        if check_forbidden(al, c): r["forbidden_hits"].append(c)
    if required: r["required_score"] = len(r["required_hits"]) / len(required)
    r["forbidden_score"] = max(0, 1.0 - len(r["forbidden_hits"]) * 0.2)
    r["total_score"] = r["required_score"] * 0.7 + r["forbidden_score"] * 0.3
    return r


def run_eval():
    with open(Path(__file__).parent / "scenarios.yaml") as f:
        scenarios = yaml.safe_load(f)["scenarios"]

    print("Loading embedding model...")
    embedder = load_embedder()

    try:
        requests.get("http://localhost:11434/api/tags", timeout=3)
        print(f"Ollama connected ({EVAL_MODEL})")
    except:
        print("ERROR: Ollama not running"); sys.exit(1)

    total_q = sum(len(s["questions"]) for s in scenarios)
    print(f"\nLLM EVAL | Model: {EVAL_MODEL} | Top-K: {TOP_K}")
    print(f"Scenarios: {len(scenarios)} | Questions: {total_q}")
    print(f"{'='*70}\n")

    all_results, total_questions, total_score, q_num = [], 0, 0, 0

    for scenario in scenarios:
        print(f"SCENARIO: {scenario['name']}")
        for q in scenario["questions"]:
            mid, question = q["module"], q["question"]
            required = q.get("required_concepts", [])
            forbidden = q.get("forbidden_concepts", [])
            if not (DB_DIR / f"{mid}.db").exists(): continue

            total_questions += 1; q_num += 1
            chunks = retrieve(mid, question, embedder)
            context = "\n\n---\n\n".join(f"[{c['title']}]\n{c['text']}" for c in chunks)
            sources = list(dict.fromkeys(c["title"] for c in chunks))
            answer = ask_ollama(question, context, scenario["context"])
            score = score_answer(answer, required, forbidden)
            total_score += score["total_score"]
            grade = "PASS" if score["total_score"] >= 0.6 else "FAIL"
            icon = "+" if grade == "PASS" else "X"
            print(f"  [{icon}] ({q_num}/{total_q}) [{mid}] {question[:55]}...")
            print(f"      Score: {score['total_score']:.0%} | Req: {score['required_score']:.0%} | Forb: {score['forbidden_score']:.0%}")
            if score["required_misses"]:
                print(f"      Missing: {', '.join(score['required_misses'])}")
            all_results.append({"scenario": scenario.get("id",""), "module": mid,
                "question": question, "answer": answer[:500], "sources": sources,
                "score": score, "grade": grade})
            time.sleep(0.3)
        print()

    avg = total_score / total_questions if total_questions else 0
    passed = sum(1 for r in all_results if r["grade"] == "PASS")
    failed = total_questions - passed

    print(f"{'='*70}")
    print(f"LLM EVAL COMPLETE | Model: {EVAL_MODEL} | Top-K: {TOP_K}")
    print(f"{'='*70}")
    print(f"  Questions: {total_questions} | Passed: {passed} | Failed: {failed} | Avg: {avg:.0%}")

    mods = {}
    for r in all_results:
        mid = r["module"]
        if mid not in mods: mods[mid] = {"scores":[], "pass":0, "fail":0}
        mods[mid]["scores"].append(r["score"]["total_score"])
        mods[mid]["pass" if r["grade"]=="PASS" else "fail"] += 1

    print(f"\n  {'Module':<28} {'Avg':>5} {'Pass':>5} {'Fail':>5} {'Rate':>6}")
    print(f"  {'-'*28} {'-'*5} {'-'*5} {'-'*5} {'-'*6}")
    passing = 0
    for mid in sorted(mods, key=lambda m: sum(mods[m]["scores"])/len(mods[m]["scores"]), reverse=True):
        s = mods[mid]; a = sum(s["scores"])/len(s["scores"]); rate = s["pass"]/(s["pass"]+s["fail"])
        if rate >= 0.6: passing += 1
        print(f"  [{'+'if rate>=0.6 else'X'}] {mid:<26} {a:>4.0%} {s['pass']:>5} {s['fail']:>5} {rate:>5.0%}")
    print(f"\n  Modules passing: {passing}/{len(mods)}")

    report = {"run_at": datetime.now().isoformat(), "model": EVAL_MODEL, "top_k": TOP_K,
        "total_questions": total_questions, "passed": passed, "failed": failed,
        "average_score": round(avg,3), "results": all_results}
    rp = RESULTS_DIR / f"eval_llm_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(rp, "w") as f: json.dump(report, f, indent=2, default=str)
    print(f"\n  Report: {rp}")

if __name__ == "__main__":
    run_eval()
