// swift-tools-version:3.1

import PackageDescription

let package = Package(
    name: "KituraLangNeg",
    dependencies: [
        .Package(url: "https://github.com/IBM-Swift/Kitura", majorVersion: 1, minor: 7),
    ]
)
