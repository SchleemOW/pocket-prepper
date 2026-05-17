#!/usr/bin/env python3
"""
Pocket Prepper - RAG-Only Evaluation
Tests raw chunk retrieval quality without LLM.
Measures whether the RIGHT chunks are being retrieved for each question.
"""

import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import yaml, json, re, struct, time, logging
from pathlib import Path
from datetime import datetime

logging.getLogger("sentence_transformers").setLevel(logging.ERROR)
logging.getLogger("huggingface_hub").setLevel(logging.ERROR)

DB_DIR = Path(__file__).parent.parent / "data" / "databases"
RESULTS_DIR = Path(__file__).parent / "results"
RESULTS_DIR.mkdir(exist_ok=True)

TOP_K = 15

# ── Synonyms (same as eval v3) ──
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
    "angle": ["angle", "angled", "slope", "sloped", "pitch", "pitched"],
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
    "kiln": ["kiln", "furnace", "oven", "fire"],
    "container": ["container", "vessel", "pot", "bucket", "bottle", "jar"],
    "dig": ["dig", "digging", "excavate", "hole"],
    "rain": ["rain", "rainfall", "rainwater", "precipitation"],
    "tinder": ["tinder", "kindling", "fire starter", "dry material"],
    "shelter": ["shelter", "cover", "protection", "lean-to", "debris hut"],
    "fire": ["fire", "flame", "burn", "ignite"],
    "water": ["water", "hydration", "drink", "fluid"],
    "food": ["food", "eat", "edible", "nutrition", "calories"],
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

    # Check format - plain blob or sqlite-vec
    tables = [r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]

    results = []

    if 'chunks' in tables:
        # Check if embedding column exists
        cols = [r[1] for r in conn.execute("PRAGMA table_info(chunks)").fetchall()]

        if 'embedding' in cols:
            # Plain blob format
            for row in conn.execute("SELECT id, text, title, source, embedding FROM chunks WHERE embedding IS NOT NULL"):
                rid, text, title, source, emb_blob = row
                if emb_blob is None:
                    continue
                emb = list(struct.iter_unpack('f', emb_blob))
                vec = [x[0] for x in emb]

                # Cosine distance
                dot = sum(a * b for a, b in zip(query_vec, vec))
                nA = sum(a * a for a in query_vec) ** 0.5
                nB = sum(b * b for b in vec) ** 0.5
                dist = 1.0 - (dot / (nA * nB)) if nA * nB > 0 else 2.0

                results.append((dist, text, title, source))
        else:
            # Old format with sqlite-vec
            import sqlite_vec
            conn.enable_load_extension(True)
            sqlite_vec.load(conn)
            conn.enable_load_extension(False)
            query_bytes = struct.pack(f"{len(query_vec)}f", *query_vec.tolist())
            for row in conn.execute("""
                SELECT c.text, c.title, c.source, v.distance
                FROM vectors v JOIN chunks c ON c.id = v.rowid
                WHERE v.embedding MATCH ? AND k = ?
                ORDER BY v.distance
            """, (query_bytes, top_k)):
                results.append((row[3], row[0], row[1], row[2]))

    conn.close()
    results.sort(key=lambda x: x[0])
    return [{"text": r[1], "title": r[2], "source": r[3], "distance": r[0]} for r in results[:top_k]]


def check_required(text_lower, concept):
    concept_lower = concept.lower()
    if concept_lower in SYNONYMS:
        for syn in SYNONYMS[concept_lower]:
            if syn.lower() in text_lower:
                return True
        return False
    return bool(re.search(r'\b' + re.escape(concept_lower) + r'\b', text_lower))


def score_chunks(chunks_text, required_concepts, forbidden_concepts):
    text_lower = chunks_text.lower()
    results = {"required_hits": [], "required_misses": [], "forbidden_hits": [],
               "required_score": 0.0, "forbidden_score": 0.0, "total_score": 0.0}

    for c in required_concepts:
        if check_required(text_lower, c):
            results["required_hits"].append(c)
        else:
            results["required_misses"].append(c)

    for c in forbidden_concepts:
        # For RAG-only, forbidden concepts don't apply (source text is what it is)
        pass

    if required_concepts:
        results["required_score"] = len(results["required_hits"]) / len(required_concepts)
    results["forbidden_score"] = 1.0  # No penalty for RAG-only
    results["total_score"] = results["required_score"]

    return results


def run_eval():
    scenarios_path = Path(__file__).parent / "scenarios.yaml"
    with open(scenarios_path) as f:
        data = yaml.safe_load(f)

    scenarios = data["scenarios"]

    print("Loading embedding model...")
    embedder = load_embedder()

    total_q = sum(len(s["questions"]) for s in scenarios)
    print(f"\nRAG-ONLY EVALUATION")
    print(f"Loaded {len(scenarios)} scenarios, {total_q} questions")
    print(f"Top-K: {TOP_K}")
    print(f"{'='*70}\n")

    all_results = []
    total_questions = 0
    total_score = 0
    missing = set()
    q_num = 0

    for scenario in scenarios:
        print(f"SCENARIO: {scenario['name']}")

        for q in scenario["questions"]:
            module_id = q["module"]
            question = q["question"]
            required = q.get("required_concepts", [])
            forbidden = q.get("forbidden_concepts", [])

            if not (DB_DIR / f"{module_id}.db").exists():
                missing.add(module_id)
                continue

            total_questions += 1
            q_num += 1

            chunks = retrieve(module_id, question, embedder)
            combined_text = "\n".join(c["text"] for c in chunks)
            sources = list(dict.fromkeys(c["title"] for c in chunks))
            avg_dist = sum(c["distance"] for c in chunks) / len(chunks) if chunks else 0

            score = score_chunks(combined_text, required, forbidden)
            total_score += score["total_score"]

            grade = "PASS" if score["total_score"] >= 0.6 else "FAIL"
            icon = "+" if grade == "PASS" else "X"

            print(f"  [{icon}] ({q_num}/{total_q}) [{module_id}] {question[:55]}...")
            print(f"      Score: {score['total_score']:.0%} | Hits: {len(score['required_hits'])}/{len(required)} | Avg dist: {avg_dist:.3f}")

            if score["required_misses"]:
                print(f"      Missing: {', '.join(score['required_misses'])}")

            all_results.append({
                "scenario": scenario.get("id", ""),
                "module": module_id,
                "question": question,
                "sources": sources,
                "avg_distance": round(avg_dist, 4),
                "chunks_preview": combined_text[:300],
                "score": score,
                "grade": grade,
            })

            time.sleep(0.1)
        print()

    avg_score = total_score / total_questions if total_questions > 0 else 0
    passed = sum(1 for r in all_results if r["grade"] == "PASS")
    failed = sum(1 for r in all_results if r["grade"] == "FAIL")

    print(f"{'='*70}")
    print(f"RAG-ONLY EVALUATION COMPLETE")
    print(f"{'='*70}")
    print(f"  Questions: {total_questions} | Passed: {passed} | Failed: {failed} | Avg: {avg_score:.0%}")

    module_scores = {}
    for r in all_results:
        mid = r["module"]
        if mid not in module_scores:
            module_scores[mid] = {"scores": [], "pass": 0, "fail": 0, "distances": []}
        module_scores[mid]["scores"].append(r["score"]["total_score"])
        module_scores[mid]["pass" if r["grade"] == "PASS" else "fail"] += 1
        module_scores[mid]["distances"].append(r["avg_distance"])

    print(f"\n  {'Module':<28} {'Score':>5} {'Pass':>5} {'Fail':>5} {'Rate':>6} {'AvgDist':>8}")
    print(f"  {'-'*28} {'-'*5} {'-'*5} {'-'*5} {'-'*6} {'-'*8}")

    for mid in sorted(module_scores.keys(), key=lambda m: sum(module_scores[m]["scores"])/len(module_scores[m]["scores"]), reverse=True):
        s = module_scores[mid]
        avg = sum(s["scores"]) / len(s["scores"])
        rate = s["pass"] / (s["pass"] + s["fail"])
        avg_d = sum(s["distances"]) / len(s["distances"])
        icon = "+" if rate >= 0.6 else "X"
        print(f"  [{icon}] {mid:<26} {avg:>4.0%} {s['pass']:>5} {s['fail']:>5} {rate:>5.0%} {avg_d:>8.3f}")

    failures = [r for r in all_results if r["grade"] == "FAIL"]
    if failures:
        print(f"\n  RETRIEVAL GAPS ({len(failures)}):")
        for r in failures:
            print(f"    [{r['module']}] {r['question'][:60]}...")
            if r["score"]["required_misses"]:
                print(f"      Missing from chunks: {', '.join(r['score']['required_misses'])}")
            print(f"      Avg distance: {r['avg_distance']:.3f}")

    report = {
        "run_at": datetime.now().isoformat(),
        "mode": "rag_only",
        "top_k": TOP_K,
        "total_questions": total_questions,
        "passed": passed,
        "failed": failed,
        "average_score": round(avg_score, 3),
        "results": all_results,
    }

    report_path = RESULTS_DIR / f"eval_rag_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(report_path, "w") as f:
        json.dump(report, f, indent=2, default=str)

    print(f"\n  Report: {report_path}")


if __name__ == "__main__":
    run_eval()
