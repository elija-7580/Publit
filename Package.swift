// swift-tools-version:5.9
// Builds and tests the platform-independent core (models, API client, logic) with SwiftPM,
// including on Linux CI. The iOS app itself is built from project.yml with XcodeGen.
import PackageDescription

let core = [
    "API/TransitousClient.swift",
    "API/ResponseCache.swift",
    "App/AppInfo.swift",
    "Models/TransitModels.swift",
    "Models/ModeStyle.swift",
    "Models/TransferRisk.swift",
    "Models/TripProgress.swift",
    "Util/Polyline.swift",
    "Util/LineColors.swift",
    "Util/Geo.swift",
    "Util/Formatting.swift",
    "Util/L10n.swift",
    "Util/Palette.swift",
    "Stores/StopGrouping.swift",
    "Stores/FavoritesStore.swift",
    "Stores/PlanModel.swift",
    "Stores/JSONFileStore.swift",
    "Stores/TripStore.swift",
    "Stores/TicketStore.swift",
    "Models/DeepLink.swift",
    "Models/PlaceRole.swift",
    "Models/TripStatus.swift",
    "Util/TicketLinks.swift",
    "Stores/MapStations.swift",
]

let package = Package(
    name: "Publit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    targets: [
        .target(name: "Publit", path: "Sources", sources: core),
        .testTarget(
            name: "PublitTests",
            dependencies: ["Publit"],
            path: "Tests",
            exclude: ["UI"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
