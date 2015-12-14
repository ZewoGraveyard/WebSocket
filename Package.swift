import PackageDescription

let package = Package(
	name: "WebSocket",
	dependencies: [
		.Package(url: "https://github.com/Zewo/HTTP.git", majorVersion: 0, minor: 1),
		.Package(url: "https://github.com/Zewo/Venice.git", majorVersion: 0, minor: 1)
	]
)
