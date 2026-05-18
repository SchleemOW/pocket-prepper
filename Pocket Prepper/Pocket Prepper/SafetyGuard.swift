import Foundation

/// Intercepts dangerous or out-of-scope queries before they reach RAG.
/// Returns nil if the query is safe, or a canned response string if it should be blocked.
struct SafetyGuard {

    // MARK: - Public API

    /// Returns a blocked response string if the query is unsafe, otherwise nil.
    static func check(_ query: String) -> String? {
        let q = query.lowercased()

        if matchesEmergency(q)       { return emergencyResponse }
        if matchesWeapon(q)          { return weaponResponse }
        if matchesMedicalDiagnosis(q){ return medicalResponse }
        if matchesGuarantee(q)       { return guaranteeResponse }
        if matchesHarmTopeople(q)    { return harmResponse }

        return nil // safe to proceed
    }

    // MARK: - Match rules

    private static func matchesEmergency(_ q: String) -> Bool {
        let triggers = [
            "call 911", "call the police", "call an ambulance", "call emergency",
            "call for help", "dial 911", "contact emergency services",
            "i am dying", "i'm dying", "someone is dying", "heart attack",
            "can't breathe", "cannot breathe", "i am having a stroke", "i'm having a stroke",
            "overdose", "severe bleeding", "life threatening"
        ]
        return triggers.contains { q.contains($0) }
    }

    private static func matchesWeapon(_ q: String) -> Bool {
        let triggers = [
            "make a bomb", "build a bomb", "make explosives", "build explosives",
            "make a grenade", "pipe bomb", "ied ", "improvised explosive",
            "synthesize poison", "make poison", "make nerve agent", "make sarin",
            "make mustard gas", "make meth", "synthesize drugs",
            "make a gun", "3d print a gun", "convert to full auto",
            "make a silencer", "make a suppressor"
        ]
        return triggers.contains { q.contains($0) }
    }

    private static func matchesMedicalDiagnosis(_ q: String) -> Bool {
        let triggers = [
            "diagnose me", "do i have", "what disease do i have",
            "what illness do i have", "am i sick", "is this cancer",
            "is this serious", "what's wrong with me", "whats wrong with me",
            "give me a diagnosis", "tell me my diagnosis"
        ]
        return triggers.contains { q.contains($0) }
    }

    private static func matchesGuarantee(_ q: String) -> Bool {
        let triggers = [
            "will this save my life", "guarantee my survival", "guaranteed to survive",
            "will i survive", "promise i'll survive", "promise i will survive",
            "will this definitely work", "100% survival"
        ]
        return triggers.contains { q.contains($0) }
    }

    private static func matchesHarmTopeople(_ q: String) -> Bool {
        let triggers = [
            "trap for a person", "trap for someone", "poison a person", "poison someone",
            "kill a person", "kill someone", "hurt someone", "hurt a person",
            "how to murder", "how to assault", "attack a person"
        ]
        return triggers.contains { q.contains($0) }
    }

    // MARK: - Canned responses

    private static let emergencyResponse = """
    ⚠️ EMERGENCY — CALL LOCAL EMERGENCY SERVICES NOW

    If you or someone else is in immediate danger, do not rely on this app.

    • Sweden: 112
    • US/Canada: 911
    • UK: 999
    • EU general: 112

    This app cannot call for help on your behalf. Please contact emergency services immediately.
    """

    private static let weaponResponse = """
    I can't help with that. Pocket Prepper covers legal survival skills — shelter, fire, water, first aid, navigation, and preparedness.

    If you have a legitimate survival question, try rephrasing it.
    """

    private static let medicalResponse = """
    Pocket Prepper is an informational reference only and cannot diagnose medical conditions.

    For medical concerns, please consult a qualified healthcare professional. In an emergency, call your local emergency services (112 in Sweden, 911 in the US).

    I can provide general first aid and wilderness medicine reference information if that would help.
    """

    private static let guaranteeResponse = """
    No survival resource — including this app — can guarantee any outcome. Conditions, individual health, environment, and timing all affect survival situations.

    What I can do is provide reference information from field manuals and wilderness medicine guides to help you make informed decisions. Always seek professional help when available.
    """

    private static let harmResponse = """
    I can't help with that. Pocket Prepper is designed for legal, ethical survival and preparedness skills only.
    """
}
