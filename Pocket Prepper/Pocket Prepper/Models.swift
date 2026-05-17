import Foundation

// MARK: - Module

struct Module: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let description: String
    let category: String
    let dbFileName: String
    let downloadURL: String
    let sizeMB: Double

    var isDownloaded: Bool {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return FileManager.default.fileExists(atPath: docs.appendingPathComponent(dbFileName).path)
    }
}

// MARK: - Module Registry

extension Module {
    static let baseURL = "https://github.com/SchleemOW/pocket-prepper/releases/download/v4.0"

    static let all: [Module] = [
        // ── LAYER 1: SURVIVE ──
        Module(
            id: "survival_general", name: "Survival - General",
            description: "Psychology of survival, planning, stress management, the SURVIVAL acronym.",
            category: "Survive",
            dbFileName: "survival_general.db",
            downloadURL: "\(baseURL)/survival_general.db",
            sizeMB: 6.4
        ),
        Module(
            id: "survival_fire_shelter", name: "Survival - Fire & Shelter",
            description: "Fire making techniques, emergency shelter construction, insulation.",
            category: "Survive",
            dbFileName: "survival_fire_shelter.db",
            downloadURL: "\(baseURL)/survival_fire_shelter.db",
            sizeMB: 3.8
        ),
        Module(
            id: "survival_navigation", name: "Survival - Navigation",
            description: "Celestial navigation, compass use, natural navigation, map reading.",
            category: "Survive",
            dbFileName: "survival_navigation.db",
            downloadURL: "\(baseURL)/survival_navigation.db",
            sizeMB: 5.8
        ),
        Module(
            id: "survival_desert", name: "Survival - Desert",
            description: "Desert water finding, heat management, solar stills, sand storms.",
            category: "Survive",
            dbFileName: "survival_desert.db",
            downloadURL: "\(baseURL)/survival_desert.db",
            sizeMB: 6.2
        ),
        Module(
            id: "survival_cold", name: "Survival - Cold Weather",
            description: "Hypothermia, frostbite, snow shelters, Arctic survival, ice fishing.",
            category: "Survive",
            dbFileName: "survival_cold.db",
            downloadURL: "\(baseURL)/survival_cold.db",
            sizeMB: 4.2
        ),

        // ── MEDICINE ──
        Module(
            id: "medicine_trauma", name: "Medicine - Trauma & Wounds",
            description: "Wound care, bleeding control, fractures, burns, splints, tourniquets.",
            category: "Medicine",
            dbFileName: "medicine_trauma.db",
            downloadURL: "\(baseURL)/medicine_trauma.db",
            sizeMB: 2.0
        ),
        Module(
            id: "medicine_infection", name: "Medicine - Infection & Disease",
            description: "Infection signs, common diseases, prevention, antibiotics, sanitation.",
            category: "Medicine",
            dbFileName: "medicine_infection.db",
            downloadURL: "\(baseURL)/medicine_infection.db",
            sizeMB: 3.7
        ),
        Module(
            id: "medicine_childbirth", name: "Medicine - Childbirth",
            description: "Pregnancy, safe delivery, newborn care, breastfeeding.",
            category: "Medicine",
            dbFileName: "medicine_childbirth.db",
            downloadURL: "\(baseURL)/medicine_childbirth.db",
            sizeMB: 2.0
        ),
        Module(
            id: "medicine_herbal", name: "Medicine - Herbal & Plant",
            description: "Medicinal plants, herbal remedies, natural antibiotics, traditional cures.",
            category: "Medicine",
            dbFileName: "medicine_herbal.db",
            downloadURL: "\(baseURL)/medicine_herbal.db",
            sizeMB: 1.9
        ),

        // ── LAYER 2: STABILIZE ──
        Module(
            id: "water", name: "Water",
            description: "Water sources, purification, solar stills, well digging, rainwater collection.",
            category: "Stabilize",
            dbFileName: "water.db",
            downloadURL: "\(baseURL)/water.db",
            sizeMB: 5.8
        ),
        Module(
            id: "food_foraging", name: "Food - Foraging & Hunting",
            description: "Edible plants, mushrooms, hunting, trapping, fishing, insects.",
            category: "Stabilize",
            dbFileName: "food_foraging.db",
            downloadURL: "\(baseURL)/food_foraging.db",
            sizeMB: 5.8
        ),
        Module(
            id: "food_farming", name: "Food - Agriculture",
            description: "Crop rotation, composting, seed saving, food preservation, fermentation.",
            category: "Stabilize",
            dbFileName: "food_farming.db",
            downloadURL: "\(baseURL)/food_farming.db",
            sizeMB: 1.8
        ),
        Module(
            id: "shelter_construction", name: "Shelter & Construction",
            description: "Log cabins, adobe, timber framing, bridges, sanitation infrastructure.",
            category: "Stabilize",
            dbFileName: "shelter_construction.db",
            downloadURL: "\(baseURL)/shelter_construction.db",
            sizeMB: 1.9
        ),

        // ── LAYER 3: REBUILD ──
        Module(
            id: "energy", name: "Energy Generation",
            description: "Micro-hydro, wind turbines, biogas, wood gasification, steam power.",
            category: "Rebuild",
            dbFileName: "energy.db",
            downloadURL: "\(baseURL)/energy.db",
            sizeMB: 2.0
        ),
        Module(
            id: "materials", name: "Materials & Manufacturing",
            description: "Metalworking, pottery, glassmaking, textiles, leather, toolmaking.",
            category: "Rebuild",
            dbFileName: "materials.db",
            downloadURL: "\(baseURL)/materials.db",
            sizeMB: 2.0
        ),
        Module(
            id: "chemistry", name: "Chemistry & Industry",
            description: "Soap, cement, distillation, dyes, penicillin, basic industrial chemistry.",
            category: "Rebuild",
            dbFileName: "chemistry.db",
            downloadURL: "\(baseURL)/chemistry.db",
            sizeMB: 1.9
        ),
        Module(
            id: "electronics", name: "Electronics & Communication",
            description: "Radio, telegraph, generators, batteries, Morse code, antennas.",
            category: "Rebuild",
            dbFileName: "electronics.db",
            downloadURL: "\(baseURL)/electronics.db",
            sizeMB: 3.6
        ),
        Module(
            id: "governance", name: "Governance & Society",
            description: "Community organizing, conflict resolution, trade, navigation, education.",
            category: "Rebuild",
            dbFileName: "governance.db",
            downloadURL: "\(baseURL)/governance.db",
            sizeMB: 3.6
        ),
    ]

    static let categories = ["Survive", "Medicine", "Stabilize", "Rebuild"]

    static func modules(for category: String) -> [Module] {
        all.filter { $0.category == category }
    }
}

// MARK: - Chat

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var text: String
    var sources: [String] = []

    enum Role {
        case user, assistant
    }
}

// MARK: - RAG Chunk

struct RAGChunk {
    let text: String
    let title: String
    let source: String
    let distance: Float
}
