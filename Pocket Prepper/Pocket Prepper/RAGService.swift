import Foundation
import SQLite

class RAGService {
    static let shared = RAGService()

    private var openDBs: [String: Connection] = [:]

    private func connection(for module: Module) -> Connection? {
        if let existing = openDBs[module.id] { return existing }

        let url = ModuleManager.shared.documentsURL(for: module.dbFileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("DB not found: \(url.path)")
            return nil
        }

        do {
            let conn = try Connection(url.path, readonly: true)
            openDBs[module.id] = conn
            return conn
        } catch {
            print("Failed to open DB: \(error)")
            return nil
        }
    }

    func retrieve(question: String, module: Module, topK: Int = 5) -> [RAGChunk] {
        guard let embedding = EmbeddingService.shared.embed(question) else {
            print("Embedding failed")
            return []
        }

        guard let conn = connection(for: module) else { return [] }

        var topResults: [(text: String, title: String, source: String, distance: Float)] = []

        do {
            // Simple query - embedding is a BLOB column in chunks table
            for row in try conn.prepare("SELECT text, title, source, embedding FROM chunks WHERE embedding IS NOT NULL") {
                let text = row[0] as? String ?? ""
                let title = row[1] as? String ?? ""
                let source = row[2] as? String ?? ""

                guard let blob = row[3] as? SQLite.Blob else { continue }
                let vector = blobToFloats(blob.bytes)
                if vector.isEmpty { continue }

                let dist = cosineDistance(embedding, vector)

                if topResults.count < topK {
                    topResults.append((text, title, source, dist))
                    topResults.sort { $0.distance < $1.distance }
                } else if dist < topResults.last!.distance {
                    topResults[topResults.count - 1] = (text, title, source, dist)
                    topResults.sort { $0.distance < $1.distance }
                }
            }

            print("RAG: scored chunks, top distance: \(topResults.first?.distance ?? -1)")

        } catch {
            print("RAG query failed: \(error)")
        }

        return topResults.map {
            RAGChunk(text: $0.text, title: $0.title, source: $0.source, distance: $0.distance)
        }
    }

    private func blobToFloats(_ bytes: [UInt8]) -> [Float] {
        let count = bytes.count / 4
        guard count > 0 else { return [] }
        var result = [Float](repeating: 0, count: count)
        for i in 0..<count {
            var value: Float = 0
            withUnsafeMutableBytes(of: &value) { dest in
                for b in 0..<4 { dest[b] = bytes[i * 4 + b] }
            }
            result[i] = value
        }
        return result
    }

    private func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return Float.greatestFiniteMagnitude }
        var dot: Float = 0, nA: Float = 0, nB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            nA += a[i] * a[i]
            nB += b[i] * b[i]
        }
        let d = sqrt(nA) * sqrt(nB)
        return d == 0 ? Float.greatestFiniteMagnitude : 1.0 - (dot / d)
    }

    func buildContext(from chunks: [RAGChunk]) -> String {
        chunks.map { "[\($0.title)]\n\($0.text)" }.joined(separator: "\n\n---\n\n")
    }

    func uniqueTitles(from chunks: [RAGChunk]) -> [String] {
        var seen = Set<String>()
        return chunks.compactMap { c in
            guard !seen.contains(c.title) else { return nil }
            seen.insert(c.title)
            return c.title
        }
    }

    func closeDB(for module: Module) {
        openDBs.removeValue(forKey: module.id)
    }
}
