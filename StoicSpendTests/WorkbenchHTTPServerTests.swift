import XCTest
@testable import StoicSpend

/// FR-11 工作台 HTTP 层关键测试 — 请求解析 / 响应序列化 / token 提取
final class WorkbenchHTTPServerTests: XCTestCase {

    private func makeRawRequest(method: String, target: String, headers: [String: String] = [:], body: String = "") -> Data {
        var head = "\(method) \(target) HTTP/1.1\r\n"
        head += "Host: 127.0.0.1\r\n"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        if !body.isEmpty {
            head += "Content-Length: \(body.utf8.count)\r\n"
        }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(Data(body.utf8))
        return data
    }

    // MARK: - 请求解析

    func testParseGetWithQueryAndHeaders() throws {
        let raw = makeRawRequest(
            method: "GET", target: "/api/summary?month=2026-11",
            headers: ["X-Auth-Token": "tok-123"]
        )
        let req = WorkbenchHTTPServer.parse(raw)
        XCTAssertNotNil(req)
        XCTAssertEqual(req?.method, "GET")
        XCTAssertEqual(req?.path, "/api/summary")
        XCTAssertEqual(req?.query["month"], "2026-11")
        XCTAssertEqual(req?.headers["x-auth-token"], "tok-123", "header key 应小写化")
        XCTAssertEqual(req?.token, "tok-123")
    }

    func testParsePostBody() throws {
        let body = "{\"code\":\"2580\"}"
        let req = WorkbenchHTTPServer.parse(makeRawRequest(method: "POST", target: "/api/pair",
                                                           headers: ["Content-Type": "application/json"], body: body))
        XCTAssertNotNil(req)
        XCTAssertEqual(req?.body.count, body.utf8.count)
        XCTAssertEqual(String(decoding: req?.body ?? Data(), as: UTF8.self), body)
    }

    func testParseIncompleteBodyReturnsNil() throws {
        // Content-Length 声明 100 但只发了 3 字节 → 未收完应返回 nil（继续等待）
        var raw = "POST /api/pair HTTP/1.1\r\nContent-Length: 100\r\n\r\n{\"a\""
        raw += String(repeating: "\u{0}", count: 0)
        let data = Data(raw.utf8)
        let req = WorkbenchHTTPServer.parse(data)
        XCTAssertNil(req, "body 未收完时不应解析出请求")
    }

    func testParseGarbageReturnsNil() throws {
        XCTAssertNil(WorkbenchHTTPServer.parse(Data("hello world".utf8)))
        XCTAssertNil(WorkbenchHTTPServer.parse(Data()))
    }

    func testTokenPriorityQueryOverHeader() throws {
        let raw = makeRawRequest(method: "GET", target: "/api/expenses?token=from-query",
                                 headers: ["X-Auth-Token": "from-header"])
        let req = WorkbenchHTTPServer.parse(raw)
        XCTAssertEqual(req?.token, "from-query", "URL token 应优先于 header")
    }

    func testTokenFromCookie() throws {
        let raw = makeRawRequest(method: "GET", target: "/",
                                 headers: ["Cookie": "foo=bar; token=cookie-tok"])
        let req = WorkbenchHTTPServer.parse(raw)
        XCTAssertEqual(req?.token, "cookie-tok")
    }

    // MARK: - 响应序列化

    func testResponseSerializationBasics() throws {
        let response = HTTPResponse.error(401, "请先输入配对码")
        let text = String(decoding: response.serialized, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
        XCTAssertTrue(text.contains("Content-Type: application/json; charset=utf-8"))
        XCTAssertTrue(text.contains("Connection: close\r\n"))
        // Content-Length 与实际 body 字节数一致
        let bodyStart = text.range(of: "\r\n\r\n")!.upperBound
        let body = text[bodyStart...]
        let declared = Int(text.split(separator: "\r\n").first(where: { $0.hasPrefix("Content-Length:") })!
            .dropFirst("Content-Length:".count).trimmingCharacters(in: .whitespaces))!
        XCTAssertEqual(declared, body.utf8.count, "Content-Length 必须与 body 字节数一致")
        XCTAssertTrue(body.contains("请先输入配对码"))
    }

    func testAttachmentResponseHasContentDisposition() throws {
        let response = HTTPResponse.data(Data([0xEF, 0xBB, 0xBF]), contentType: "text/csv; charset=utf-8", filename: "stoicspend_export.csv")
        let text = String(decoding: response.serialized, as: UTF8.self)
        XCTAssertTrue(text.contains("Content-Disposition: attachment; filename=\"stoicspend_export.csv\""))
    }
}
