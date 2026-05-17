import requests
import trafilatura
import time
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

WIKIPEDIA_API = "https://en.wikipedia.org/w/api.php"
HEADERS = {"User-Agent": "DoomsdayRAG/1.0 (survival knowledge base; offline prep app)"}


def fetch_wikipedia_page(title, retries=4):
    params = {"action": "query", "titles": title, "prop": "extracts", "explaintext": True, "exsectionformat": "plain", "format": "json", "redirects": 1}
    for attempt in range(retries):
        try:
            resp = requests.get(WIKIPEDIA_API, params=params, headers=HEADERS, timeout=15)
            if resp.status_code == 429:
                wait = 8 * (attempt + 1)
                logger.warning(f"    Rate limited, waiting {wait}s... (attempt {attempt+1}/{retries})")
                time.sleep(wait)
                continue
            resp.raise_for_status()
            pages = resp.json().get("query", {}).get("pages", {})
            for page in pages.values():
                if "extract" in page and len(page["extract"]) > 200:
                    return page["extract"]
            return None
        except Exception as e:
            if "429" in str(e):
                time.sleep(8 * (attempt + 1))
            else:
                logger.error(f"    Wikipedia error '{title}': {e}")
                if attempt < retries - 1: time.sleep(3)
    return None


class IngestionAgent:
    def run(self, state):
        raw_docs = []
        for source in state["sources"]:
            src_type = source["type"]
            try:
                if src_type == "wikipedia_articles":
                    docs = self._ingest_wikipedia_articles(source)
                elif src_type == "pdf":
                    docs = self._ingest_pdf(source)
                elif src_type == "local_pdf":
                    docs = self._ingest_local_pdf(source)
                elif src_type == "multi_pdf":
                    docs = self._ingest_multi_pdf(source)
                elif src_type == "web":
                    docs = self._ingest_web(source)
                else:
                    continue
                raw_docs.extend(docs)
                logger.info(f"  + {src_type}: {len(docs)} documents")
            except Exception as e:
                logger.error(f"  Failed {src_type}: {e}")
        state["raw_docs"] = raw_docs
        return state

    def _ingest_wikipedia_articles(self, source):
        docs = []
        for title in source["titles"]:
            text = fetch_wikipedia_page(title)
            if not text: continue
            docs.append({"text": text, "source": f"wikipedia:{title}", "title": title, "license": source["license"], "priority": source["priority"]})
            time.sleep(1.5)
        return docs

    def _ingest_pdf(self, source):
        try:
            from pypdf import PdfReader
            import io
            resp = requests.get(source["url"], headers=HEADERS, timeout=60)
            if resp.status_code != 200: return []
            reader = PdfReader(io.BytesIO(resp.content))
            docs = []
            for i, page in enumerate(reader.pages):
                text = page.extract_text()
                if text and len(text.strip()) > 100:
                    docs.append({"text": text, "source": source.get("url",""), "title": source.get("title",""), "page": i, "license": source["license"], "priority": source["priority"]})
            return docs
        except Exception as e:
            logger.error(f"    PDF download failed: {e}")
            return []

    def _ingest_local_pdf(self, source):
        """Read a PDF from the local filesystem."""
        try:
            from pypdf import PdfReader
            filepath = source["path"]
            # Resolve relative to project root
            if not Path(filepath).is_absolute():
                filepath = Path(__file__).parent.parent / filepath
            filepath = Path(filepath)
            if not filepath.exists():
                logger.error(f"    Local PDF not found: {filepath}")
                return []
            reader = PdfReader(str(filepath))
            docs = []
            for i, page in enumerate(reader.pages):
                text = page.extract_text()
                if text and len(text.strip()) > 100:
                    docs.append({"text": text, "source": str(filepath.name), "title": source.get("title", filepath.stem), "page": i, "license": source["license"], "priority": source["priority"]})
            logger.info(f"    Read {len(docs)} pages from {filepath.name}")
            return docs
        except Exception as e:
            logger.error(f"    Local PDF failed: {e}")
            return []

    def _ingest_multi_pdf(self, source):
        all_docs = []
        urls = source.get("urls", [])
        title = source.get("title", "PDF")
        logger.info(f"    Downloading {len(urls)} PDFs for '{title}'...")
        for i, url in enumerate(urls):
            try:
                docs = self._ingest_pdf({"url": url, "title": title, "license": source["license"], "priority": source["priority"]})
                all_docs.extend(docs)
                if docs: logger.info(f"    [{i+1}/{len(urls)}] {len(docs)} pages")
                time.sleep(0.5)
            except Exception as e:
                logger.error(f"    Failed {url}: {e}")
        return all_docs

    def _ingest_web(self, source):
        try:
            downloaded = trafilatura.fetch_url(source["url"])
            if not downloaded: return []
            text = trafilatura.extract(downloaded, include_tables=True)
            if not text or len(text) < 200: return []
            return [{"text": text, "source": source["url"], "title": source.get("title",""), "license": source["license"], "priority": source["priority"]}]
        except Exception as e:
            logger.error(f"    Web failed: {e}")
            return []
