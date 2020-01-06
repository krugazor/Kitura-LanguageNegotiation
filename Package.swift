// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "KituraLangNeg",
    products: [
        .library(
            name: "KituraLangNeg",
            targets: ["KituraLangNeg"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/IBM-Swift/Kitura.git", from: "2.9.0"),
    ],
    targets: [
        .target(
            name: "KituraLangNeg",
            dependencies: ["Kitura"]
            ),
        .testTarget(
            name: "KituraLangNegTests",
            dependencies: ["KituraLangNeg"]),

    ]
)
