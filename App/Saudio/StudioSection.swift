import Foundation

/// Kept so older views and menu commands still compile after the dashboard redesign.
enum StudioSection: String, CaseIterable, Identifiable {
    case studio
    case createVoice
    case chat
    case dialogue
    case lab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studio: return "Studio"
        case .createVoice: return "Create Voice"
        case .chat: return "Chat"
        case .dialogue: return "Dialogue"
        case .lab: return "Lab"
        }
    }

    var icon: String {
        switch self {
        case .studio: return "waveform"
        case .createVoice: return "mic"
        case .chat: return "bubble.left"
        case .dialogue: return "person.2"
        case .lab: return "flask"
        }
    }
}
