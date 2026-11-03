// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: [ SwiftSetting ] =
[
 .enableUpcomingFeature("ApproachableConcurrency"),
 .enableUpcomingFeature("MemberImportVisibility"),
 .enableUpcomingFeature("ExistentialAny")
]

let package = Package(name: "VLNetworkKit",
                      defaultLocalization: "en",
                      platforms: [ .iOS(.v17) ],
                      products:
                      [
                       .library(name: "VLNetworkKit",
                                targets: [ "VLNetworkKit" ])
                      ],
                      dependencies:
                      [
                       .package(url: "https://github.com/VLstack/VLBundleKit", from: "1.5.1"),
                       .package(url: "https://github.com/VLstack/VLStringKit", from: "2.5.1")
                      ],
                      targets:
                      [
                       .target(name: "VLNetworkKit",
                               dependencies: [ "VLBundleKit", "VLStringKit" ],
                               resources: [ .process("Resources") ],
                               swiftSettings: swiftSettings),
                       .testTarget(name: "VLNetworkKitTests",
                                   dependencies: [ "VLNetworkKit" ],
                                   swiftSettings: swiftSettings)
                      ])
