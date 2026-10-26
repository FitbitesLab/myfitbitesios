import AppIntents
import WidgetKit

// WidgetKit persists this intent per instance; no global preference overrides another widget.
enum WidgetCompanion: String, AppEnum {
    case tiel, too, both
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Companion"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.tiel: "Tiel", .too: "Too", .both: "Too & Tiel"]
}

enum WidgetAppearance: String, AppEnum {
    case cream, espresso, system
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Appearance"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.cream: "Warm cream", .espresso: "Espresso dark", .system: "Follow system"]
}

struct CompanionConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Your Fitbites widget"
    static var description = IntentDescription("Choose the companion and appearance for this widget.")
    @Parameter(title: "Companion", default: .tiel) var companion: WidgetCompanion
    @Parameter(title: "Appearance", default: .cream) var appearance: WidgetAppearance
    @Parameter(title: "Comments (medium and large)", default: true) var comments: Bool
    static var parameterSummary: some ParameterSummary {
        Summary { \.$companion; \.$appearance; \.$comments }
    }
}


// Today has content categories, not a character picker: each role uses its approved pose.
enum TodayContent: String, AppEnum {
    case automatic, lab, member, recipe, arcade
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Content"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .automatic: "Daily rotation", .lab: "Too’s creations", .member: "My level & tier",
        .recipe: "Featured recipe", .arcade: "My Arcade"
    ]
    var kind: WidgetTodayKind? { WidgetTodayKind(rawValue: rawValue) }
}

struct TodayConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Today at Fitbites"
    static var description = IntentDescription("One featured card each day: creations, recipes, your progress, and Arcade.")
    @Parameter(title: "Content", default: .automatic) var content: TodayContent
    @Parameter(title: "Appearance", default: .cream) var appearance: WidgetAppearance
    @Parameter(title: "Character comments", default: true) var comments: Bool
    static var parameterSummary: some ParameterSummary {
        Summary { \.$content; \.$appearance; \.$comments }
    }
}
