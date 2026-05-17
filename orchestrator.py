#!/usr/bin/env python3
"""
Doomsday RAG Pipeline Orchestrator
Builds offline survival knowledge databases from public sources.
"""

import argparse
import json
import logging
import sys
import time
import yaml
from pathlib import Path
from datetime import datetime

from agents.ingestion import IngestionAgent
from agents.processing import ProcessingAgent
from agents.embedding import EmbeddingAgent
from agents.database import DatabaseAgent

# ── Logging setup ─────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(message)s",
    datefmt="%H:%M:%S",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler("data/pipeline.log", encoding="utf-8"),
    ]
)

# Fix Windows terminal unicode issues
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
logger = logging.getLogger(__name__)


def load_modules(config_path: str = "config/modules.yaml") -> list:
    with open(config_path) as f:
        return yaml.safe_load(f)["modules"]


def run_module(module: dict, agents: dict) -> dict:
    state = {
        "module_id":     module["id"],
        "module_name":   module["name"],
        "sources":       module["sources"],
        "raw_docs":      [],
        "cleaned_chunks": [],
        "embeddings":    [],
    }

    t0 = time.time()

    state = agents["ingestion"].run(state)
    state = agents["processing"].run(state)
    state = agents["embedding"].run(state)
    state = agents["database"].run(state)

    elapsed = round(time.time() - t0, 1)

    return {
        "module_id":   module["id"],
        "module_name": module["name"],
        "docs":        len(state["raw_docs"]),
        "chunks":      state.get("chunk_count", 0),
        "db_path":     state.get("db_path"),
        "elapsed_s":   elapsed,
        "status":      "ok" if state.get("db_path") else "failed",
    }


def run_pipeline(module_ids: list = None, config_path: str = "config/modules.yaml"):
    Path("data").mkdir(exist_ok=True)

    modules = load_modules(config_path)
    if module_ids:
        modules = [m for m in modules if m["id"] in module_ids]

    if not modules:
        logger.error("No matching modules found.")
        sys.exit(1)

    logger.info(f"\n{'='*60}")
    logger.info(f"  DOOMSDAY RAG PIPELINE")
    logger.info(f"  Modules to process: {len(modules)}")
    logger.info(f"  Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info(f"{'='*60}\n")

    # Load agents once (embedding model loads once)
    agents = {
        "ingestion":  IngestionAgent(),
        "processing": ProcessingAgent(),
        "embedding":  EmbeddingAgent(),
        "database":   DatabaseAgent(),
    }

    results = []
    for i, module in enumerate(modules, 1):
        logger.info(f"\n[{i}/{len(modules)}] Module: {module['name']}")
        logger.info(f"  {module.get('description', '')}")
        logger.info(f"  {'-'*40}")

        result = run_module(module, agents)
        results.append(result)

        status_icon = "✓" if result["status"] == "ok" else "✗"
        logger.info(
            f"  {status_icon} Done — {result['docs']} docs, "
            f"{result['chunks']} chunks, {result['elapsed_s']}s"
        )

    # ── Summary ───────────────────────────────────────────────────────────────
    logger.info(f"\n{'='*60}")
    logger.info("  PIPELINE COMPLETE")
    logger.info(f"{'='*60}")

    total_chunks = 0
    total_mb = 0

    for r in results:
        icon = "✓" if r["status"] == "ok" else "✗"
        db_size = ""
        if r["db_path"] and Path(r["db_path"]).exists():
            mb = Path(r["db_path"]).stat().st_size / 1024 / 1024
            total_mb += mb
            db_size = f"  {mb:.1f} MB"
        total_chunks += r["chunks"]
        logger.info(
            f"  {icon} {r['module_name']:<30} "
            f"{r['chunks']:>5} chunks{db_size}"
        )

    logger.info(f"\n  Total chunks : {total_chunks:,}")
    logger.info(f"  Total DB size: {total_mb:.1f} MB")
    logger.info(f"  Databases in : data/databases/\n")

    # Save run report
    report_path = "data/pipeline_report.json"
    with open(report_path, "w") as f:
        json.dump({
            "run_at": datetime.now().isoformat(),
            "modules": results,
            "total_chunks": total_chunks,
            "total_mb": round(total_mb, 2),
        }, f, indent=2)

    logger.info(f"  Report saved: {report_path}")
    return results


def query_db(module_id: str, question: str, top_k: int = 5):
    """Test query against a built database."""
    import sqlite3
    import sqlite_vec
    import struct
    from agents.embedding import EmbeddingAgent

    db_path = Path(f"data/databases/{module_id}.db")
    if not db_path.exists():
        print(f"Database not found: {db_path}")
        return

    embedder = EmbeddingAgent()
    query_vec = embedder.model.encode([question], normalize_embeddings=True)[0]
    query_bytes = struct.pack(f"{len(query_vec)}f", *query_vec.tolist())

    conn = sqlite3.connect(str(db_path))
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)
    conn.enable_load_extension(False)

    rows = conn.execute("""
        SELECT c.text, c.source, c.title, v.distance
        FROM vectors v
        JOIN chunks c ON c.id = v.rowid
        WHERE v.embedding MATCH ?
          AND k = ?
        ORDER BY v.distance
    """, (query_bytes, top_k)).fetchall()

    conn.close()

    print(f"\n{'='*60}")
    print(f"Query: {question}")
    print(f"Module: {module_id}")
    print(f"{'='*60}\n")

    for i, (text, source, title, dist) in enumerate(rows, 1):
        print(f"[{i}] {title} (dist: {dist:.4f})")
        print(f"    Source: {source}")
        print(f"    {text[:300]}...")
        print()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Doomsday RAG Pipeline")
    subparsers = parser.add_subparsers(dest="command")

    # Build command
    build_parser = subparsers.add_parser("build", help="Build RAG databases")
    build_parser.add_argument("--modules", nargs="*", help="Module IDs to build (default: all)")

    # Query command
    query_parser = subparsers.add_parser("query", help="Test query a database")
    query_parser.add_argument("module", help="Module ID")
    query_parser.add_argument("question", help="Question to ask")
    query_parser.add_argument("--top-k", type=int, default=5)

    args = parser.parse_args()

    if args.command == "build":
        run_pipeline(module_ids=args.modules)
    elif args.command == "query":
        query_db(args.module, args.question, args.top_k)
    else:
        # Default: build all
        run_pipeline()
