#!/usr/bin/env python3
"""
Pocket Prepper - Quality Evaluation Runner v3
Improved scoring with stemming and synonym matching.
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import yaml
import json
import re
import time
import struct
import logging
import requests
from pathlib import Path
from datetime import datetime

logging.getLogger("sentence_transformers").setLevel(logging.ERROR)
logging.getLogger("huggingface_hub").setLevel(logging.ERROR)

DB_DIR = Path(__file__).parent.parent / "data" / "databases"
RESULTS_DIR = Path(__file__).parent / "results"
RESULTS_DIR.mkdir(exist_ok=True)

OLLAMA_URL = "http://localhost:11434/api/generate"
EVAL_MODEL = "mistral"
TOP_K = 15

# ── Synonym map: if any synonym is found, the concept is considered matched ──
SYNONYMS = {
    "filter": ["filter", "filtering", "filtration", "strain", "straining", "sieve"],
    "boil": ["boil", "boiling", "boiled"],
    "cloth": ["cloth", "fabric", "clothing", "shirt", "bandana", "rag"],
    "distill": ["distill", "distillation", "distilling", "evaporate", "evaporation"],
    "condense": ["condense", "condensation", "condensing", "collect steam"],
    "clean": ["clean", "cleaning", "cleanliness", "wash", "washing", "sanitize"],
    "sealed": ["sealed", "seal", "airtight", "closed", "covered", "lid"],
    "container": ["container", "vessel", "pot", "bucket", "bottle", "jar", "tank"],
    "dark": ["dark", "shade", "cool place", "away from light", "sunlight"],
    "trap": ["trap", "trapping", "traps", "snare", "snaring", "deadfall"],
    "snare": ["snare", "snaring", "trap", "trapping", "noose", "loop"],
    "net": ["net", "netting", "seine", "gill net", "mesh"],
    "weir": ["weir", "dam", "fish trap", "obstruction", "channel"],
    "hunt": ["hunt", "hunting", "hunted", "track", "stalk"],
    "bark": ["bark", "cambium", "inner bark", "tree bark"],
    "cricket": ["cricket", "grasshopper", "insect", "grub", "worm", "larvae"],
    "larvae": ["larvae", "grub", "grubs", "worm", "worms", "maggot"],
    "avoid bright": ["avoid bright", "brightly colored", "bright color", "hairy", "stinging"],
    "milky sap": ["milky sap", "milky or discolored sap", "milky", "discolored sap"],
    "almond smell": ["almond smell", "smell of almonds", "almonds", "bitter almond", "cyanide"],
    "coconut": ["coconut", "palm", "palm tree"],
    "shellfish": ["shellfish", "clam", "mussel", "oyster", "crab", "crustacean", "mollusk"],
    "fruit": ["fruit", "fruits", "berries", "berry"],
    "star": ["star", "stars", "celestial", "polaris", "north star", "constellation"],
    "compass": ["compass", "direction", "bearing", "magnetic"],
    "landmark": ["landmark", "landmarks", "reference point", "terrain feature"],
    "council": ["council", "committee", "assembly", "representatives", "elected"],
    "consensus": ["consensus", "agreement", "majority", "vote", "democratic"],
    "meeting": ["meeting", "meetings", "gather", "discussion", "assembly"],
    "oral": ["oral", "verbal", "spoken", "storytelling", "word of mouth"],
    "apprentice": ["apprentice", "apprenticeship", "mentor", "hands-on", "learn by doing"],
    "practice": ["practice", "practical", "hands-on", "experience", "doing"],
    "skill": ["skill", "skills", "craft", "trade", "ability", "technique"],
    "gradual": ["gradual", "gradually", "slowly", "slow", "gentle", "gently"],
    "skin": ["skin", "tissue", "flesh", "affected area"],
    "ice fishing": ["ice fishing", "fishing through ice", "frozen", "ice hole"],
    "coal": ["coal", "coals", "ember", "embers", "charcoal"],
    "log": ["log", "logs", "large wood", "thick wood", "heavy wood"],
    "slow": ["slow", "slowly", "overnight", "smolder", "bank"],
    "wall": ["wall", "walls", "windbreak", "barrier", "wind block"],
    "waterproof": ["waterproof", "waterproofing", "water resistant", "rain proof", "shed water"],
    "insulation": ["insulation", "insulate", "insulating", "warmth", "heat retention", "thermal"],
    "leaves": ["leaves", "leaf", "foliage", "debris", "vegetation"],
    "branches": ["branches", "branch", "bough", "limbs", "sticks"],
    "angle": ["angle", "angled", "slope", "sloped", "pitch", "pitched"],
    "friction": ["friction", "rubbing", "rub"],
    "bow drill": ["bow drill", "bow-drill", "bow and drill", "fire bow"],
    "smoke": ["smoke", "smoking", "smoked", "smoky"],
    "mirror": ["mirror", "reflection", "reflective", "signal mirror", "shiny"],
    "debris": ["debris", "rubble", "wreckage"],
    "breathe": ["breathe", "breathing", "breath", "airway", "air"],
    "signal": ["signal", "signaling", "signalling", "attract attention"],
    "plan": ["plan", "planning", "strategy", "prioritize", "think"],
    "priorities": ["priorities", "priority", "prioritize", "most important", "first"],
    "calm": ["calm", "calming", "relax", "composure", "panic", "stress", "fear"],
    "hole": ["hole", "pit", "dig", "excavation", "depression"],
    "condensation": ["condensation", "condense", "moisture", "droplets", "dew"],
    "sun": ["sun", "solar", "sunlight", "sunshine"],
    "heat": ["heat", "hot", "temperature", "warm", "scorching"],
    "conserve": ["conserve", "conservation", "preserve", "minimize", "reduce"],
    "shade": ["shade", "shadow", "shelter", "cover", "protected"],
    "bamboo": ["bamboo", "pole", "poles"],
    "palm": ["palm", "palm leaves", "fronds", "coconut"],
    "frame": ["frame", "framework", "structure", "skeleton"],
    "elevated": ["elevated", "raised", "off ground", "platform", "stilts"],
    "thatch": ["thatch", "thatching", "thatched", "palm leaves", "grass roof"],
    "overlap": ["overlap", "overlapping", "layered", "layers"],
    "pitch": ["pitch", "pitched", "angle", "slope", "steep"],
    "conscious": ["conscious", "consciousness", "awake", "alert", "responsive"],
    "pupil": ["pupil", "pupils", "eyes", "dilated", "unequal"],
    "sleep": ["sleep", "drowsy", "drowsiness", "lethargy", "unconscious"],
    "uterus": ["uterus", "womb", "belly", "abdomen", "fundus"],
    "breastfeed": ["breastfeed", "breastfeeding", "nurse", "nursing", "nipple"],
    "massage": ["massage", "rub", "rubbing", "knead"],
    "airway": ["airway", "airways", "mouth", "nose", "clear the mouth"],
    "stimulate": ["stimulate", "stimulation", "rub the back", "flick feet", "tap"],
    "clear": ["clear", "clearing", "remove", "suction", "wipe"],
    "fresh water": ["fresh water", "freshwater", "clean water", "potable", "drinking water"],
    "honey": ["honey"],
    "bandage": ["bandage", "dressing", "wrap", "cloth", "cover"],
    "rain": ["rain", "rainfall", "rainwater", "precipitation"],
    "dig": ["dig", "digging", "excavate", "hole"],
    "propagate": ["propagate", "propagation", "grow from", "reproduce", "clone", "cutting"],
    "cutting": ["cutting", "cuttings", "stem", "clone", "divide"],
    "salt": ["salt", "salted", "salting", "sodium"],
    "ferment": ["ferment", "fermentation", "fermenting", "fermented", "culture"],
    "potato": ["potato", "potatoes", "tuber", "tubers", "root vegetable"],
    "bean": ["bean", "beans", "legume", "legumes", "pulse"],
    "squash": ["squash", "pumpkin", "gourd", "melon"],
    "spear": ["spear", "spearing", "spearfish", "gig", "gigging", "sharp stick"],
    "trail": ["trail", "path", "track", "tracks", "game trail", "animal path"],
    "bait": ["bait", "lure", "attract", "food"],
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
    import sqlite_vec

    db_path = DB_DIR / f"{module_id}.db"
    if not db_path.exists():
        return []

    query_vec = embedder.encode([question], normalize_embeddings=True)[0]
    query_bytes = struct.pack(f"{len(query_vec)}f", *query_vec.tolist())

    conn = sqlite3.connect(str(db_path))
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)
    conn.enable_load_extension(False)

    rows = conn.execute("""
        SELECT c.text, c.title, c.source, v.distance
        FROM vectors v
        JOIN chunks c ON c.id = v.rowid
        WHERE v.embedding MATCH ? AND k = ?
        ORDER BY v.distance
    """, (query_bytes, top_k)).fetchall()
    conn.close()

    return [{"text": r[0], "title": r[1], "source": r[2], "distance": r[3]} for r in rows]


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
            "model": EVAL_MODEL,
            "system": system,
            "prompt": prompt,
            "stream": False,
        }, timeout=120)
        return resp.json().get("response", "")
    except Exception as e:
        return f"[ERROR: {e}]"


# ── Phrase-aware forbidden checking ──
AMBIGUOUS_FORBIDDEN = {
    "store": [r'\b(go to|visit|find|the|a) store\b', r'\bgrocery store\b', r'\bhardware store\b'],
    "school": [r'\b(go to|attend|enroll|the|a) school\b'],
    "doctor": [r'\b(see|call|visit|consult|find) (a |the )?doctor\b'],
    "hospital": [r'\b(go to|visit|take .* to|nearest|the|a) hospital\b'],
}


def check_forbidden(answer_lower, concept):
    concept_lower = concept.lower()
    if concept_lower in AMBIGUOUS_FORBIDDEN:
        for pattern in AMBIGUOUS_FORBIDDEN[concept_lower]:
            if re.search(pattern, answer_lower):
                return True
        return False
    pattern = r'\b' + re.escape(concept_lower) + r'\b'
    return bool(re.search(pattern, answer_lower))


def check_required(answer_lower, concept):
    """Check if a required concept (or any synonym) appears in the answer."""
    concept_lower = concept.lower()

    # Check synonyms first
    if concept_lower in SYNONYMS:
        for syn in SYNONYMS[concept_lower]:
            if syn.lower() in answer_lower:
                return True
        return False

    # Fallback: word boundary match
    pattern = r'\b' + re.escape(concept_lower) + r'\b'
    return bool(re.search(pattern, answer_lower))


def score_answer(answer, required_concepts, forbidden_concepts):
    answer_lower = answer.lower()
    results = {
        "required_hits": [],
        "required_misses": [],
        "forbidden_hits": [],
        "required_score": 0.0,
        "forbidden_score": 0.0,
        "total_score": 0.0,
    }

    for concept in required_concepts:
        if check_required(answer_lower, concept):
            results["required_hits"].append(concept)
        else:
            results["required_misses"].append(concept)

    for concept in forbidden_concepts:
        if check_forbidden(answer_lower, concept):
            results["forbidden_hits"].append(concept)

    if required_concepts:
        results["required_score"] = len(results["required_hits"]) / len(required_concepts)

    forbidden_penalty = len(results["forbidden_hits"]) * 0.2
    results["forbidden_score"] = max(0, 1.0 - forbidden_penalty)

    results["total_score"] = results["required_score"] * 0.7 + results["forbidden_score"] * 0.3

    return results


def run_eval():
    scenarios_path = Path(__file__).parent / "scenarios.yaml"
    with open(scenarios_path) as f:
        data = yaml.safe_load(f)

    scenarios = data["scenarios"]

    print("Loading embedding model...")
    embedder = load_embedder()

    try:
        requests.get("http://localhost:11434/api/tags", timeout=3)
        print(f"Ollama connected ({EVAL_MODEL})")
    except:
        print("ERROR: Ollama not running. Start with: ollama serve")
        sys.exit(1)

    total_q = sum(len(s["questions"]) for s in scenarios)
    print(f"\nLoaded {len(scenarios)} scenarios, {total_q} questions")
    print(f"Top-K: {TOP_K} | Scoring: synonym-aware v3")
    print(f"{'='*70}\n")

    all_results = []
    total_questions = 0
    total_score = 0
    missing_modules = set()
    q_num = 0

    for scenario in scenarios:
        print(f"SCENARIO: {scenario['name']}")
        print()

        for q in scenario["questions"]:
            module_id = q["module"]
            question = q["question"]
            required = q.get("required_concepts", [])
            forbidden = q.get("forbidden_concepts", [])

            if not (DB_DIR / f"{module_id}.db").exists():
                missing_modules.add(module_id)
                continue

            total_questions += 1
            q_num += 1

            chunks = retrieve(module_id, question, embedder)
            context = "\n\n---\n\n".join(f"[{c['title']}]\n{c['text']}" for c in chunks)
            sources = list(dict.fromkeys(c["title"] for c in chunks))

            answer = ask_ollama(question, context, scenario["context"])
            score = score_answer(answer, required, forbidden)
            total_score += score["total_score"]

            grade = "PASS" if score["total_score"] >= 0.6 else "FAIL"
            grade_icon = "+" if grade == "PASS" else "X"

            print(f"  [{grade_icon}] ({q_num}/{total_q}) [{module_id}] {question[:55]}...")
            print(f"      Score: {score['total_score']:.0%} | Req: {score['required_score']:.0%} | Forb: {score['forbidden_score']:.0%}")

            if score["required_misses"]:
                print(f"      Missing: {', '.join(score['required_misses'])}")
            if score["forbidden_hits"]:
                print(f"      FORBIDDEN: {', '.join(score['forbidden_hits'])}")

            all_results.append({
                "scenario": scenario["id"],
                "module": module_id,
                "question": question,
                "answer": answer[:500],
                "sources": sources,
                "score": score,
                "grade": grade,
            })

            time.sleep(0.3)

        print()

    avg_score = total_score / total_questions if total_questions > 0 else 0
    passed = sum(1 for r in all_results if r["grade"] == "PASS")
    failed = sum(1 for r in all_results if r["grade"] == "FAIL")

    print(f"{'='*70}")
    print(f"EVALUATION COMPLETE")
    print(f"{'='*70}")
    print(f"  Questions: {total_questions} | Passed: {passed} | Failed: {failed} | Avg: {avg_score:.0%}")

    print(f"\n  {'Module':<30} {'Avg':>5} {'Pass':>5} {'Fail':>5} {'Rate':>6}")
    print(f"  {'-'*30} {'-'*5} {'-'*5} {'-'*5} {'-'*6}")

    module_scores = {}
    for r in all_results:
        mid = r["module"]
        if mid not in module_scores:
            module_scores[mid] = {"scores": [], "pass": 0, "fail": 0}
        module_scores[mid]["scores"].append(r["score"]["total_score"])
        module_scores[mid]["pass" if r["grade"] == "PASS" else "fail"] += 1

    passing_modules = 0
    for mid in sorted(module_scores.keys(), key=lambda m: sum(module_scores[m]["scores"])/len(module_scores[m]["scores"]), reverse=True):
        s = module_scores[mid]
        avg = sum(s["scores"]) / len(s["scores"])
        total = s["pass"] + s["fail"]
        rate = s["pass"] / total
        icon = "+" if rate >= 0.6 else "X"
        if rate >= 0.6: passing_modules += 1
        print(f"  [{icon}] {mid:<28} {avg:>4.0%} {s['pass']:>5} {s['fail']:>5} {rate:>5.0%}")

    print(f"\n  Modules passing: {passing_modules}/{len(module_scores)}")

    failures = [r for r in all_results if r["grade"] == "FAIL"]
    if failures:
        print(f"\n  STILL FAILING ({len(failures)}):")
        for r in failures:
            misses = r["score"]["required_misses"]
            print(f"    [{r['module']}] {r['question'][:60]}...")
            if misses: print(f"      Missing: {', '.join(misses)}")

    report = {
        "run_at": datetime.now().isoformat(),
        "model": EVAL_MODEL,
        "top_k": TOP_K,
        "scoring": "synonym-aware-v3",
        "total_questions": total_questions,
        "passed": passed,
        "failed": failed,
        "average_score": round(avg_score, 3),
        "results": all_results,
    }

    report_path = RESULTS_DIR / f"eval_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(report_path, "w") as f:
        json.dump(report, f, indent=2, default=str)

    print(f"\n  Report: {report_path}")


if __name__ == "__main__":
    run_eval()
