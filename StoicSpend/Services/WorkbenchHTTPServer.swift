import Foundation
import Network

/// FR-11 电脑端工作台 — 极简 HTTP/1.1 服务器（Network.framework，无第三方依赖）
/// 每连接处理单个请求后关闭（Connection: close），仅监听本地接口
struct HTTPRequest {
    var method: String
    var path: String                 // 不含 query
    var query: [String: String]
    var headers: [String: String]    // key 全小写
    var body: Data

    /// token：URL query ?token= / X-Auth-Token 头 / Cookie
    var token: String? {
        if let t = query["token"], !t.isEmpty { return t }
        if let t = headers["x-auth-token"], !t.isEmpty { return t }
        if let cookie = headers["cookie"] {
            for pair in cookie.split(separator: ";") {
                let kv = pair.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
                if kv.count == 2, kv[0] == "token" { return String(kv[1]) }
            }
        }
        return nil
    }
}

struct HTTPResponse {
    var status: Int
    var contentType: String
    var body: Data
    var extraHeaders: [String: String] = [:]

    static func json(_ string: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "application/json; charset=utf-8",
                     body: Data(string.utf8))
    }

    static func html(_ string: String) -> HTTPResponse {
        HTTPResponse(status: 200, contentType: "text/html; charset=utf-8", body: Data(string.utf8))
    }

    static func data(_ data: Data, contentType: String, filename: String) -> HTTPResponse {
        var r = HTTPResponse(status: 200, contentType: contentType, body: data)
        r.extraHeaders["Content-Disposition"] = "attachment; filename=\"\(filename)\""
        return r
    }

    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "application/json; charset=utf-8",
                     body: Data("{\"error\":\"\(message)\"}".utf8))
    }

    private var statusText: String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        default: return "Error"
        }
    }

    var serialized: Data {
        var head = "HTTP/1.1 \(status) \(statusText)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        for (k, v) in extraHeaders { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        var out = Data(head.utf8)
        out.append(body)
        return out
    }
}

/// HTTP 服务器 — 请求处理回调在内部串行队列调用；返回端口经 onReady 回调
final class WorkbenchHTTPServer {
    var handler: ((HTTPRequest) -> HTTPResponse)?
    private var listener: NWListener?
    private var readyReported = false
    private let queue = DispatchQueue(label: "com.zhenglin.stoicspend.workbench.http")

    /// 启动监听；onReady 在内部队列回调（携带实际端口）
    /// 首选端口被占（.failed EADDRINUSE）时自动回退系统分配端口
    func start(preferredPort: UInt16 = 8787, onReady: @escaping (UInt16) -> Void) {
        stop()
        startListener(port: NWEndpoint.Port(rawValue: preferredPort) ?? .any, fallbackLevel: 0, onReady: onReady)
    }

    private var onReadyHandler: ((UInt16) -> Void)?

    private func startListener(port: NWEndpoint.Port, fallbackLevel: Int, onReady: @escaping (UInt16) -> Void) {
        stop()
        onReadyHandler = onReady
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: params, on: port) else { return }

        // Bonjour 广播 — 同 Wi-Fi 免输 IP 发现（PRD FR-11）
        // 模拟器等环境下 Bonjour 注册可能失败，按级回退：端口回退 → 放弃广播
        if fallbackLevel < 2 {
            listener.service = NWListener.Service(name: "Stoic Spend", type: "_stoicspend._tcp")
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready, .waiting:
                // 模拟器/部分环境下 Bonjour 注册会进入 waiting，但端口已可监听
                if let p = listener.port?.rawValue, !self.readyReported {
                    self.readyReported = true
                    self.onReadyHandler?(p)
                }
            case .failed:
                if !self.readyReported && fallbackLevel < 2 {
                    // L0→L1: 换系统分配端口；L1→L2: 再放弃 Bonjour 广播
                    let nextPort: NWEndpoint.Port = fallbackLevel == 0 ? .any : port
                    self.startListener(port: nextPort, fallbackLevel: fallbackLevel + 1, onReady: onReady)
                } else {
                    self.stop()
                }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        readyReported = false
    }

    // MARK: - 连接处理

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }

            if error != nil || isComplete {
                // 客户端已关，尝试解析已收到的完整请求（浏览器可能先发后关）
                if let request = Self.parse(buf) {
                    self.respond(to: request, on: conn)
                } else {
                    conn.cancel()
                }
                return
            }

            if let request = Self.parse(buf) {
                self.respond(to: request, on: conn)
            } else if buf.count > 10_000_000 {
                self.send(HTTPResponse.error(413, "Request too large"), on: conn)
            } else {
                self.receive(conn, buffer: buf)
            }
        }
    }

    private func respond(to request: HTTPRequest, on conn: NWConnection) {
        let response = handler?(request) ?? HTTPResponse.error(404, "Not Found")
        send(response, on: conn)
    }

    private func send(_ response: HTTPResponse, on conn: NWConnection) {
        conn.send(content: response.serialized, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    // MARK: - HTTP 解析

    /// internal — 单元测试可见
    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let target = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines {
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = line[..<idx].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        // query 解析
        var path = target
        var query: [String: String] = [:]
        if let qIdx = target.firstIndex(of: "?") {
            path = String(target[..<qIdx])
            for pair in target[target.index(after: qIdx)...].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                guard let k = kv.first.map(String.init)?.removingPercentEncoding else { continue }
                query[k] = kv.count > 1 ? (String(kv[1]).removingPercentEncoding ?? "") : ""
            }
        }

        // body
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart >= contentLength else { return nil }  // 未收完
        let body = data[bodyStart..<(bodyStart + contentLength)]

        return HTTPRequest(method: method, path: path, query: query, headers: headers, body: Data(body))
    }
}
