#!/usr/bin/env python3
"""
Pocket Prepper - Mac query interface
Uses phi-3-mini-4bit via MLX + RAG databases
"""

try:
    from pysqlite3 import dbapi2 as sqlite3
except ImportError:
    import sqlite3
import sqlite_vec
import struct
import logging
from pathlib import Path

logging.getLogger("sentence_transformers").setLevel(logging.ERROR)
logging.getLogger("huggingface_hub").setLevel(logging.ERROR)
logging.getLogger("transformers").setLevel(logging.ERROR)

MODEL_ID = "mlx-community/Phi-3-mini-4k-instruct-4bit"
DB_DIR   = Path.home() / "Desktop" / "pocket-prepper" / "data" / "databases"

MODULE_NAMES = {
    "survival":             "Immediate Survival",
    "medicine":             "Medicine & Health",
    "food_water":           "Food & Water",
    "shelter_construction": "Shelter & Construction",
    "energy":               "Energy Generation",
    "materials":            "Materials & Manufacturing",
    "chemistry":            "Chemistry & Industry",
    "electronics":          "Electronics & Communication",
    "governance":           "Governance & Society",
}

SYSTEM_PROMPT = (
    "You are a practical survival and civilization-rebuilding expert. "
    "Answer using ONLY the provided context. Be specific and actionable. "
    "If the context lacks enough detail, say so - never invent information."
)

def load_model():
    from mlx_lm import load
    print(f"Loading {MODEL_ID}...")
    model, tokenizer = load(MODEL_ID)
    print("Model ready.\n")
    return model, tokenizer

def load_embedder():
    from sentence_transformers import SentenceTransformer
    print("Loading embedding model...")
    return SentenceTransformer("all-MiniLM-L6-v2")

def retrieve(module_id: str, question: str, embedder, top_k: int = 5) -> list:
    db_path = DB_DIR / f"{module_id}.db"
    if not db_path.exists():
        print(f"[!] Database not found: {db_path}")
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

def ask_phi3(question: str, context: str, model, tokenizer) -> str:
    from mlx_lm import stream_generate

    prompt = f"""CONTEXT FROM SURVIVAL KNOWLEDGE BASE:
{context}

QUESTION: {question}

ANSWER (based only on the context above):"""

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user",   "content": prompt},
    ]

    formatted = tokenizer.apply_chat_template(
        messages, tokenize=False, add_generation_prompt=True,
    )

    print("\nAssistant: ", end="", flush=True)
    full = ""
    for response in stream_generate(model, tokenizer, prompt=formatted, max_tokens=512):
        token = response.text if hasattr(response, "text") else str(response)
        print(token, end="", flush=True)
        full += token
    print("\n")
    return full

def pick_module() -> str:
    print("\nAvailable knowledge modules:")
    modules = list(MODULE_NAMES.items())
    for i, (mid, name) in enumerate(modules, 1):
        status = "ready" if (DB_DIR / f"{mid}.db").exists() else "NOT BUILT"
        print(f"  {i}. {name:<35} [{status}]")
    print()
    while True:
        choice = input("Pick a module (1-9): ").strip()
        if choice.isdigit() and 1 <= int(choice) <= len(modules):
            return modules[int(choice) - 1][0]
        print("  Invalid, try again.")

def chat_loop(module_id: str, model, tokenizer, embedder):
    name = MODULE_NAMES.get(module_id, module_id)
    print(f"\n{'='*60}")
    print(f"  POCKET PREPPER  -  {name.upper()}")
    print(f"  Type 'switch' to change module | 'quit' to exit")
    print(f"{'='*60}\n")

    while True:
        try:
            question = input("You: ").strip()
        except (KeyboardInterrupt, EOFError):
            print("\nExiting.")
            break

        if not question:
            continue
        if question.lower() in ("quit", "exit", "q"):
            print("Exiting.")
            break
        if question.lower() == "switch":
            module_id = pick_module()
            name = MODULE_NAMES.get(module_id, module_id)
            print(f"Switched to: {name}\n")
            continue

        chunks = retrieve(module_id, question, embedder)
        if not chunks:
            print("No relevant context found.\n")
            continue

        context = "\n\n---\n\n".join(
            f"[{c['title']}]\n{c['text']}" for c in chunks
        )
        titles = list(dict.fromkeys(c["title"] for c in chunks))
        print(f"Sources: {', '.join(titles)}")
        ask_phi3(question, context, model, tokenizer)

def main():
    embedder = load_embedder()
    model, tokenizer = load_model()
    module_id = pick_module()
    chat_loop(module_id, model, tokenizer, embedder)

if __name__ == "__main__":
    main()