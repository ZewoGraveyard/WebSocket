import PackageDescription

let package = Package(
    name: "WebSocket",
    dependencies: [
        .Package(url: "https://github.com/Zewo/Event.git",  majorVersion: 0, minor: 10),
        .Package(url: "https://github.com/Zewo/Base64.git", majorVersion: 0, minor: 10),
        .Package(url: "https://github.com/Zewo/POSIX.git", majorVersion: 0, minor: 10),
    ]
)
