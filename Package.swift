// swift-tools-version: 5.9
import PackageDescription

// A dependency-free test harness for the shared native engine. Open the .xcodeproj to run the App.
let package = Package(
    name: "MacbookAccordionCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AccordionCore", targets: ["AccordionCore"])],
    targets: [
        .target(name: "AccordionCore", path: "Native/Core"),
        .testTarget(name: "AccordionCoreTests", dependencies: ["AccordionCore"], path: "Native/Tests", resources: [.copy("LegacyContract.json")])
    ]
)
