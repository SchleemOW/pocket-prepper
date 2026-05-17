import re
import logging
from langchain_text_splitters import RecursiveCharacterTextSplitter

logger = logging.getLogger(__name__)

class ProcessingAgent:
    def __init__(self):
        self.splitter = RecursiveCharacterTextSplitter(
            chunk_size=600,
            chunk_overlap=60,
            separators=["\n\n", "\n", ". ", "! ", "? ", " "],
        )

    def run(self, state: dict) -> dict:
        cleaned_chunks = []

        for doc in state["raw_docs"]:
            cleaned_text = self._clean(doc["text"])
            if len(cleaned_text) < 150:
                continue

            chunks = self.splitter.split_text(cleaned_text)

            for chunk in chunks:
                score = self._quality_score(chunk)
                if score < 0.45:
                    continue

                cleaned_chunks.append({
                    "text": chunk,
                    "source": doc["source"],
                    "title": doc.get("title", ""),
                    "license": doc["license"],
                    "priority": doc["priority"],
                    "module": state["module_id"],
                    "quality_score": round(score, 2),
                })

        logger.info(f"  Processing: {len(state['raw_docs'])} docs → {len(cleaned_chunks)} chunks")
        state["cleaned_chunks"] = cleaned_chunks
        return state

    def _clean(self, text: str) -> str:
        # Collapse excessive newlines
        text = re.sub(r'\n{3,}', '\n\n', text)
        # Collapse spaces
        text = re.sub(r' {2,}', ' ', text)
        # Remove lone page numbers
        text = re.sub(r'(?m)^\d+$', '', text)
        # Remove URLs
        text = re.sub(r'https?://\S+', '', text)
        # Remove edit markers from Wikipedia
        text = re.sub(r'\[edit\]', '', text)
        # Remove citation markers like [1], [2]
        text = re.sub(r'\[\d+\]', '', text)
        return text.strip()

    def _quality_score(self, chunk: str) -> float:
        score = 1.0
        words = chunk.split()

        if not words:
            return 0.0

        # Penalize very short chunks
        if len(words) < 40:
            score -= 0.3

        # Penalize chunks that are mostly numbers (tables, indexes)
        num_count = sum(1 for w in words if re.match(r'^\d+[\.,]?\d*$', w))
        if len(words) > 0 and num_count / len(words) > 0.25:
            score -= 0.35

        # Penalize low lexical diversity (repetitive junk)
        unique_ratio = len(set(w.lower() for w in words)) / len(words)
        if unique_ratio < 0.4:
            score -= 0.3

        # Penalize very long words on average (binary/encoded junk)
        avg_word_len = sum(len(w) for w in words) / len(words)
        if avg_word_len > 12:
            score -= 0.2

        # Penalize chunks with no sentence-ending punctuation
        if not re.search(r'[.!?]', chunk):
            score -= 0.1

        return max(0.0, score)
