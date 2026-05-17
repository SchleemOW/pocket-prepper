import logging
import math
import hashlib
import re
import numpy as np

logger = logging.getLogger(__name__)

EMBEDDING_DIM = 384  # Same dim as all-MiniLM-L6-v2


def _try_load_sentence_transformer(model_name: str):
    """Try to load SentenceTransformer; return None if unavailable."""
    try:
        from sentence_transformers import SentenceTransformer
        model = SentenceTransformer(model_name)
        logger.info(f"  ✓ Loaded SentenceTransformer: {model_name}")
        return model
    except Exception as e:
        logger.warning(f"  SentenceTransformer unavailable ({e}), using local hashing embedder.")
        return None


class HashingEmbedder:
    """
    Offline fallback embedder using TF-IDF hashing trick.
    No model download required. Deterministic, portable.
    Quality is lower than neural embeddings but good enough for
    keyword-based RAG retrieval. Replace with SentenceTransformer
    once you run on your own machine with internet access.
    """

    def __init__(self, dim: int = EMBEDDING_DIM):
        self.dim = dim

    def _tokenize(self, text: str) -> list:
        return re.findall(r'\b[a-z]{2,}\b', text.lower())

    def _hash_token(self, token: str, seed: int = 0) -> int:
        h = hashlib.md5(f"{seed}:{token}".encode()).digest()
        return int.from_bytes(h[:4], "little") % self.dim

    def encode(self, texts: list, **kwargs) -> np.ndarray:
        results = []
        for text in texts:
            vec = np.zeros(self.dim, dtype=np.float32)
            tokens = self._tokenize(text)
            if not tokens:
                results.append(vec)
                continue

            # Bigrams + unigrams for better semantic coverage
            ngrams = tokens + [f"{a}_{b}" for a, b in zip(tokens, tokens[1:])]
            freq: dict = {}
            for ng in ngrams:
                freq[ng] = freq.get(ng, 0) + 1

            for ng, count in freq.items():
                idx = self._hash_token(ng)
                # Sign from a second hash to reduce collisions
                sign = 1 if self._hash_token(ng, seed=1) % 2 == 0 else -1
                tf = 1 + math.log(count)
                vec[idx] += sign * tf

            # L2 normalise
            norm = np.linalg.norm(vec)
            if norm > 0:
                vec /= norm

            results.append(vec)

        return np.array(results, dtype=np.float32)


class EmbeddingAgent:
    _model = None  # Shared across instances — load once

    def __init__(self, model_name: str = "all-MiniLM-L6-v2"):
        if EmbeddingAgent._model is None:
            neural = _try_load_sentence_transformer(model_name)
            EmbeddingAgent._model = neural if neural else HashingEmbedder()
        self.model = EmbeddingAgent._model

    def run(self, state: dict) -> dict:
        chunks = state["cleaned_chunks"]
        if not chunks:
            state["embeddings"] = []
            return state

        texts = [c["text"] for c in chunks]
        logger.info(f"  Embedding {len(texts)} chunks...")

        embeddings = self.model.encode(
            texts,
            batch_size=64,
            show_progress_bar=False,
            normalize_embeddings=True,
        )

        state["embeddings"] = embeddings
        return state
