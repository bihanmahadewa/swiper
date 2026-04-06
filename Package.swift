// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiperMenuBar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "SwiperMenuBar", targets: ["SwiperMenuBar"]),
    ],
    targets: [
        .executableTarget(
            name: "SwiperMenuBar",
            path: "Sources/SwiperMenuBar"
        ),
    ]
)
