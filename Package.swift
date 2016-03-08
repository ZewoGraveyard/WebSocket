import PackageDescription

#if os(OSX)
    let openSSLURL = "https://github.com/Zewo/COpenSSL-OSX.git"
#else
    let openSSLURL = "https://github.com/Zewo/COpenSSL.git"
#endif

let package = Package(
	name: "WebSocket",
	dependencies: [
		.Package(url: "https://github.com/Zewo/HTTP.git", majorVersion: 0, minor: 3),
		.Package(url: "https://github.com/Zewo/HTTPClient.git", majorVersion: 0, minor: 3),
		.Package(url: "https://github.com/Zewo/HTTPSClient.git", majorVersion: 0, minor: 3),
		.Package(url: "https://github.com/Zewo/Event.git", majorVersion: 0, minor: 2),
		.Package(url: "https://github.com/Zewo/Base64.git", majorVersion: 0, minor: 2),
		.Package(url: "https://github.com/Zewo/OpenSSL.git", majorVersion: 0, minor: 2),
		.Package(url: "https://github.com/Zewo/Venice.git", majorVersion: 0, minor: 2),
		.Package(url: "https://github.com/Zewo/CURIParser.git", majorVersion: 0, minor: 2),
		.Package(url: "https://github.com/Zewo/CHTTPParser.git", majorVersion: 0, minor: 2),
		.Package(url: "https://github.com/Zewo/CLibvenice.git", majorVersion: 0, minor: 2),
		.Package(url: openSSLURL, majorVersion: 0, minor: 2)
	]
)
