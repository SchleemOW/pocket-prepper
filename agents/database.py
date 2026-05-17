"""
Database Agent v2 - stores embeddings as plain BLOBs in chunks table.
No sqlite-vec dependency needed on iOS.
"""

import sqlite3
import struct
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

def serialize_floats(floats) -> bytes:
    return struct.pack(f"{len(floats)}f", *floats)

class DatabaseAgent:
    def __init__(self, db_dir="data/databases"):
        self.db_dir = Path(db_dir)
        self.db_dir.mkdir(parents=True, exist_ok=True)

    def run(self, state):
        module_id = state["module_id"]
        chunks = state["cleaned_chunks"]
        embeddings = state["embeddings"]

        if not chunks:
            logger.warning(f"  No chunks for {module_id}")
            state["db_path"] = None
            return state

        db_path = self.db_dir / f"{module_id}.db"
        if db_path.exists():
            db_path.unlink()

        conn = sqlite3.connect(str(db_path))

        conn.execute("""
            CREATE TABLE chunks (
                id            INTEGER PRIMARY KEY,
                text          TEXT NOT NULL,
                source        TEXT,
                title         TEXT,
                license       TEXT,
                priority      TEXT,
                module        TEXT,
                quality_score REAL,
                embedding     BLOB
            )
        """)

        conn.execute("""
            CREATE TABLE meta (
                key   TEXT PRIMARY KEY,
                value TEXT
            )
        """)

        for i, (chunk, embedding) in enumerate(zip(chunks, embeddings)):
            emb_blob = serialize_floats(embedding.tolist())
            conn.execute(
                """INSERT INTO chunks
                   (id, text, source, title, license, priority, module, quality_score, embedding)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (i,
                 chunk["text"],
                 chunk["source"],
                 chunk.get("title", ""),
                 chunk["license"],
                 chunk["priority"],
                 chunk["module"],
                 chunk.get("quality_score", 1.0),
                 emb_blob)
            )

        dim = len(embeddings[0])
        chunk_count = len(chunks)

        conn.execute("INSERT INTO meta VALUES ('module_id', ?)", (module_id,))
        conn.execute("INSERT INTO meta VALUES ('chunk_count', ?)", (str(chunk_count),))
        conn.execute("INSERT INTO meta VALUES ('embedding_dim', ?)", (str(dim),))
        conn.execute("INSERT INTO meta VALUES ('format', 'plain_blob')")

        conn.commit()
        conn.close()

        size_mb = db_path.stat().st_size / 1024 / 1024
        logger.info(f"  Written {chunk_count} chunks to {db_path} ({size_mb:.1f} MB)")

        state["db_path"] = str(db_path)
        state["chunk_count"] = chunk_count
        return state
