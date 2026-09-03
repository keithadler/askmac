// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AskMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AskMac", path: "Sources/AskMac",
                          linkerSettings: [.linkedFramework("PDFKit"), .linkedFramework("NaturalLanguage"), .linkedFramework("Quartz"), .linkedFramework("Vision"), .linkedFramework("Carbon"),
                                           // Apple's on-device language model exists from macOS 26; weak so the app still runs on 14 and 15.
                                           .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"])]),
        .testTarget(name: "AskMacTests", dependencies: ["AskMac"], path: "Tests/AskMacTests"),
    ]
)
