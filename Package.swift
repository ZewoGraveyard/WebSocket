import PackageDescription

let package = Package(
	name: "WebSockets",
	dependencies: [
		.Package(url: "https://github.com/Zewo/HTTP.git", majorVersion: 0, minor: 1),
		.Package(url: "https://github.com/Zewo/Venice.git", majorVersion: 0, minor: 1)
	]
)
