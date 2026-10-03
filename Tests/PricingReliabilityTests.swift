import Foundation
actor FakeServer {
    var statuses: [Int]
    var calls = 0
    var active = 0
    var maxActive = 0
    let retryAfter: String?
    init(_ statuses: [Int], retryAfter: String? = nil) { self.statuses=statuses;self.retryAfter=retryAfter }
    func load(_ request: URLRequest) async throws -> (Data,URLResponse) {
        calls += 1; active += 1; maxActive = max(maxActive,active)
        defer { active -= 1 }
        try await Task.sleep(for:.milliseconds(10))
        let status = statuses.count > 1 ? statuses.removeFirst() : statuses[0]
        if status == -1 { throw URLError(.timedOut) }
        return (Data("{}".utf8),HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:retryAfter.map { ["Retry-After":$0] })!)
    }
}
@main struct PricingReliabilityTests {
    static func main() async throws {
        func check(_ value: Bool,_ message: String) { precondition(value,message) }
        let request=URLRequest(url:URL(string:"https://example.invalid/test")!)
        for statuses in [[503,200],[-1,200],[429,200]] {
            let server=FakeServer(statuses,retryAfter:"0")
            let transport=TCGTransport(loader:{ try await server.load($0) },pause:{ _ in })
            _ = try await transport.send(request)
            check(await server.calls == 2,"Temporary failures retry and recover")
        }
        let denied=FakeServer([403])
        let blocked=TCGTransport(loader:{ try await denied.load($0) },pause:{ _ in })
        for _ in 0..<2 {
            do { _ = try await blocked.send(request); fatalError("403 must fail") }
            catch let error as TCGServiceError { check(error.status == 403 && error.retryAt != nil,"Denied access has explicit cooldown") }
        }
        check(await denied.calls == 1,"Cooldown prevents repeated access-denied requests")
        let throttled=FakeServer([429],retryAfter:"120")
        let limited=TCGTransport(loader:{ try await throttled.load($0) },pause:{ _ in })
        do { _ = try await limited.send(request); fatalError("Long Retry-After must pause") }
        catch let error as TCGServiceError { check(error.retryAt!.timeIntervalSinceNow > 115,"Respect server Retry-After") }
        check(await throttled.calls == 1,"No immediate retry against server cooldown")
        let broken=FakeServer([503])
        let bounded=TCGTransport(loader:{ try await broken.load($0) },pause:{ _ in })
        do { _ = try await bounded.send(request); fatalError("Persistent failure must surface") } catch {}
        check(await broken.calls == 3,"Retries are bounded")
        let server=FakeServer([200])
        let queue=TCGTransport(loader:{ try await server.load($0) },pause:{ _ in })
        try await withThrowingTaskGroup(of:Void.self) { group in
            for _ in 0..<8 { group.addTask { _ = try await queue.send(request) } }
            try await group.waitForAll()
        }
        check(await server.calls == 8,"All queued requests finish")
        check(await server.maxActive == 1,"Manual and background requests never overlap")
        let cancelled=Task { _ = try await queue.send(request) };cancelled.cancel()
        do { try await cancelled.value; fatalError("Cancellation must propagate") } catch is CancellationError {}
        check(TCGTransport.retryDelay("120") == 120,"Numeric retry delay")
        check(TCGTransport.retryDelay("Wed, 21 Oct 2015 07:28:00 GMT",now:Date(timeIntervalSince1970:1445412420)) == 60,"HTTP date retry delay")
        print("Pricing reliability checks passed: retry, cooldown, rate limiting, serialization and cancellation.")
    }
}
