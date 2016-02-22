import PackageDescription

let package = Package(
	name: "WebSocket",
	dependencies: [
		.Package(url: "https://github.com/Zewo/HTTP.git", majorVersion: 0, minor: 2),
		.Package(url: "https://github.com/Zewo/HTTPClient.git", majorVersion: 0, minor: 2),
		.Package(url: "https://github.com/Zewo/HTTPSClient.git", majorVersion: 0, minor: 2),
		.Package(url: "https://github.com/Zewo/Event.git", majorVersion: 0, minor: 2),
		.Package(url: "https://github.com/Zewo/Base64.git", majorVersion: 0, minor: 2),
		.Package(url: "https://github.com/Zewo/OpenSSL.git", majorVersion: 0, minor: 2),
		.Package(url: "https://github.com/Zewo/Venice.git", majorVersion: 0, minor: 2)
	]
)
