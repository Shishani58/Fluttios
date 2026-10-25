import Foundation

/// Accept only a locally served DevTools page, never an arbitrary URL printed by an app.
public enum DevToolsLink {
    public static func url(from value: String?) -> URL? {
        guard let value, let components = URLComponents(string: value),
            isLocal(components, schemes: ["http", "https"]), let url = components.url
        else { return nil }
        for item in components.queryItems ?? [] where item.name == "uri" || item.name == "dtdUri" {
            guard let value = item.value, let service = URLComponents(string: value),
                isLocal(service, schemes: ["http", "https", "ws", "wss"])
            else { return nil }
        }
        return url
    }

    private static func isLocal(_ components: URLComponents, schemes: Set<String>) -> Bool {
        guard let scheme = components.scheme?.lowercased(), schemes.contains(scheme),
            let host = components.host?.lowercased(), ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host),
            let port = components.port, (1...65535).contains(port),
            components.user == nil, components.password == nil
        else { return false }
        return true
    }
}
