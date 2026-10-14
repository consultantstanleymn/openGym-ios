// swift-tools-version: 6.0

import PackageDescription

// A plain SwiftPM package. xtool takes the named product from xtool.yml and builds it into an
// .app — there is no .xcodeproj, no CocoaPods, and no storyboards anywhere in this project.
//
// That is the whole reason the app is written this way. openGym's own iOS target is a Capacitor
// project: an Xcode project, eight CocoaPods, Main.storyboard, LaunchScreen.storyboard and an
// Assets.xcassets. None of that is reachable from SwiftPM — @capacitor/ios ships only podspecs —
// and xtool cannot read a storyboard or compile an asset catalog. See README.md.
//
// Deployment target 17.4 is a floor, not a preference. The app bundle runs openGym's mobile
// build, and that build calls structuredClone() unguarded in twelve places across routine and
// workout editing (routines.js, Workout.jsx, RoutineEdit.jsx, Plan.jsx). structuredClone shipped
// in Safari 17.4; on anything older those paths throw and core editing breaks.
let package = Package(
    name: "openGym",
    platforms: [
        .iOS("17.4"),
        .macOS(.v14),
    ],
    products: [
        // xtool wants a library product and supplies the app's entry point and bundle itself;
        // this matches Examples/DemoSimple in the xtool repository.
        .library(
            name: "openGym",
            targets: ["openGym"]
        )
    ],
    targets: [
        .target(
            name: "openGym",
            path: "Sources/openGym",
            resources: [
                // The built web bundle. Copied in by scripts/build-web.sh, which runs
                // VITE_MOBILE=1 vite build plus the media staging step, and points VITE_NATIVE_SHIM
                // at src/native. Not in git: it is a build product, and .gitignore says so.
                .copy("WebBundle")
            ]
        )
    ]
)