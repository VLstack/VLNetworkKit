// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

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
                       .package(url: "https://github.com/VLstack/VLstackNamespace", from: "1.2.0"),
                       .package(url: "https://github.com/VLstack/VLBundleKit", from: "1.5.1")
                      ],
                      targets:
                      [
                       .target(name: "VLNetworkKit",
                               dependencies: [ "VLstackNamespace", "VLBundleKit" ],
                               resources: [ .process("Resources") ])
                      ])
