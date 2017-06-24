import XCTest
import Foundation
import Kitura
import KituraNet
@testable import KituraLangNeg

class KituraLangNegTests: XCTestCase {

    static var allTests = [
        ("testBadConfigs", testBadConfigs),
        ("testHeaderDetection", testHeaderDetection),
        ("testPathDetection", testPathDetection),
        // Unsure how to test this without having the user tweak their hosts
        // file. =/
        ("testDomainDetection", testDomainDetection)
    ]

    func testBadConfigs() {
        do {
            _ = try LanguageNegotiation([], methods: [.subdomain], options: [])
            XCTFail("Error not thrown when using empty langs")
        }
        catch LanguageNegotiation.NegMethodError.InitWithNoLangs {
            // Pass
        }
        catch {
            XCTFail("Wrong error thrown when using empty langs")
        }

        do {
            _ = try LanguageNegotiation(["en"], methods: [])
            XCTFail("Error not thrown when using empty methods")
        }
        catch LanguageNegotiation.NegMethodError.InitWithNoMethods {
            // Pass
        }
        catch {
            XCTFail("Wrong error thrown when using empty methods")
        }

        do {
            _ = try LanguageNegotiation(["en"], methods: [.subdomain, .pathPrefix], options: [])
            XCTFail("Error not thrown when using conflicting methods")
        }
        catch LanguageNegotiation.NegMethodError.SubdomainAndPathPrefix {
            // Pass
        }
        catch {
            XCTFail("Wrong error thron when using conflicting methods")
        }


        do {
            _ = try LanguageNegotiation(["en"], methods: [.header], options: [.redirectOnHeaderMatch])
            XCTFail("Error not thrown when redirecting nowhere")
        }
        catch LanguageNegotiation.NegMethodError.RedirectWhere {
            // Pass
        }
        catch {
            XCTFail("Wrong error thrown when redirecting nowhere")
        }
    }

    func testHeaderDetection() {
        let ln = try! LanguageNegotiation(["en", "ja"], methods: [.header])
        let r = setupRouter(langNeg: ln)
        performServerTest(router: r) { expectation in
            self.perfReq(headers: ["Accept-Language": "ja"], callback: { response in
                XCTAssertEqual(response!.headers["Content-Language"]!.first!, "ja", "Simple Accept-Language negotiation failed")
            })
            self.perfReq(headers: ["Accept-Language": "zh-hans"], callback: { response in
                XCTAssertEqual(response!.headers["Content-Language"]!.first!, "en", "Default fallback on negotiation failure failed")
            })
            self.perfReq(headers: ["Accept-Language": "zh-hans,en;q=0.9,ja;q=0.6"], callback: { response in
                guard let negMatch = self.buildNegMatch(response: response!) else {
                    XCTFail("Couldn't build negMatch from response")
                    return
                }
                XCTAssertEqual(negMatch.lang, "en", "Simple Accept-Language negotiation with quality component failed")
                XCTAssertEqual(negMatch.quality, 0.9, "Unexpected quality value when negotiating with quality component")
            })
            // @todo: redirection
            expectation.fulfill()
        }

        // @todo Cannot currently test redirects because the request code
        // is actually following redirects! Can't stop that from happening as
        // far as I can see. Workaround?

//        let ln2 = try! LanguageNegotiation(["en", "ja"], methods: [.header, .pathPrefix], options: [.redirectOnHeaderMatch])
//        let r2 = setupRouter(langNeg: ln2)
//        performServerTest(router: r2) { expectation in
//            self.perfReq(headers: ["Accept-Language": "ja"], callback: { response in
//                XCTAssertEqual(response!.headers["Location"]!.first!, "http://localhost/ja/test", "Path prefix redirection not working as expected")
//            })
//            expectation.fulfill()
//        }

//        let ln3 = try! LanguageNegotiation(["en", "ja"], methods: [.header, .subdomain], options: [.redirectOnHeaderMatch])
//        let r3 = setupRouter(langNeg: ln3)
//        performServerTest(router: r3) { expectation in
//            self.perfReq(headers: ["Accept-Language": "ja"], callback: { response in
//                XCTAssertEqual(response!.headers["Location"]!.first!, "http://ja.localhost/test", "Subdomain redirection not working as expected")
//            })
//            expectation.fulfill()
//        }
    }

    func testPathDetection() {
        let ln = try! LanguageNegotiation(["en", "ja", "de"], methods: [.pathPrefix])
        let r = Router()
        let sr = setupRouter()
        r.all(ln.routerPaths, allowPartialMatch: true, middleware: [ln, sr])
        performServerTest(router: r) { expectation in
            self.perfReq(path: "/de/test", callback: { response in
                guard let negMatch = self.buildNegMatch(response: response!) else {
                    XCTFail("Couldn't build negMatch from response")
                    return
                }
                if negMatch.lang != "de" || negMatch.method != .PathPrefix {
                    XCTFail("Simple path-based matching failed")
                }
            })
            expectation.fulfill()
        }
    }

    func testOptions() {
        let ln = try! LanguageNegotiation(["en", "ja", "de"], methods: [.header, .pathPrefix], options: [.notAcceptableOnHeaderMatchFail])
        let r = Router()
        let sr = setupRouter()
        r.all(ln.routerPaths, allowPartialMatch: true, middleware: [ln, sr])
        r.all("/test", middleware: ln)
        performServerTest(router: r) { expectation in
            self.perfReq(path: "/de/test", callback: { response in
                guard let langHeader = response!.headers["Content-Language"] else {
                    XCTFail("No Content-Language header when expected")
                    return
                }
                XCTAssertEqual(langHeader.first!, "de", "Wrong Content-Language header encountered")
            })
            self.perfReq(headers: ["Accept-Language": "zh-hans"], callback: {
                response in
                XCTAssertEqual(response!.statusCode, HTTPStatusCode.notAcceptable, "No Not Acceptable HTTP status when expected")
                guard let varyHeader = response!.headers["Vary"] else {
                    XCTFail("No Vary header when expected")
                    return
                }
                XCTAssertEqual(varyHeader.first!, "Accept-Language", "Wrong Vary header encountered")
           })
            expectation.fulfill()
        }

        let ln2 = try! LanguageNegotiation(["en", "de"], methods: [.header], options: [.noContentLanguage, .noVary])
        let r2 = setupRouter(langNeg: ln2)
        performServerTest(router: r2) { expectation in
            self.perfReq(headers: ["Accept-Langauge": "de"], callback: { response in
                XCTAssertNil(response!.headers["Vary"], "Vary header present when not expected")
                XCTAssertNil(response!.headers["Content-Language"], "Content-Language header present when not expected")
            })
            expectation.fulfill()

        }
    }

    func testDomainDetection() {
        let ln = try! LanguageNegotiation(["en", "ja", "de"], methods: [.subdomain])
        let r = setupRouter(langNeg: ln)
        performServerTest(router: r) { expectation in
            self.perfReq(host: "ja.localhost", path: "/test", callback: { response in
                guard let negMatch = self.buildNegMatch(response: response!) else {
                    XCTFail("Couldn't build negMatch from response")
                    return
                }
                XCTAssertEqual(negMatch.lang, "ja", "Simple subdomain-based matching failed (please add en.localhost, de.localhost, and ja.localhost to your hosts file, all pointing to 127.0.0.1; else this test will always fail)")
            })
            expectation.fulfill()
        }

    }

    func buildNegMatch(response: ClientResponse) -> LanguageNegotiation.NegMatch? {
        guard let lang = response.headers["X-NM-Lang"], let quality = response.headers["X-NM-Quality"], let method = response.headers["X-NM-Method"] else {
            return nil
        }
        // Silly hack to get an enum value from a hash value
        let negMethods: [LanguageNegotiation.NegMethod] = [.Subdomain, .PathPrefix, .Header, .Default, .Failure]
        var foundMethod: LanguageNegotiation.NegMethod?
        for negMethod in negMethods {
            if method.first! == String(negMethod.hashValue) {
                foundMethod = negMethod
                break
            }
        }
        if foundMethod == nil {
            return nil
        }

        return LanguageNegotiation.NegMatch(lang: lang.first!, method: foundMethod!, quality: Float(quality.first!)!)
    }

    func setupRouter(langNeg: LanguageNegotiation? = nil) -> Router {
        let r = Router()
        if let langNeg = langNeg {
            r.all(middleware: langNeg)
        }
        r.all("/test") { request, response, next in
            defer {
                next()
            }
            if let negMatch: LanguageNegotiation.NegMatch = request.userInfo["LangNeg"]! as? LanguageNegotiation.NegMatch {
                response.headers["X-NM-Lang"] = negMatch.lang
                response.headers["X-NM-Quality"] = String(negMatch.quality)
                response.headers["X-NM-Method"] = String(negMatch.method.hashValue)

            }
        }
        return r
    }


    // Ripped off from the Kitura-CredentialsHTTP tests.
    func performServerTest(router: ServerDelegate, asyncTasks: @escaping (XCTestExpectation) -> Void...) {
        do {
            let server = try HTTPServer.listen(on: 8090, delegate: router)
            let requestQueue = DispatchQueue(label: "Request queue")

            for (index, asyncTask) in asyncTasks.enumerated() {
                let expectation = self.expectation(index)
                requestQueue.async {
                    asyncTask(expectation)
                }
            }

            waitExpectation(timeout: 10) { error in
                // blocks test until request completes
                server.stop()
                XCTAssertNil(error);
            }
        } catch {
            XCTFail("Error: \(error)")
        }
    }

    func performRequest(method: String, host: String = "localhost", path: String, callback: @escaping ClientRequest.Callback, headers: [String: String]? = nil, requestModifier: ((ClientRequest) -> Void)? = nil) {
        var allHeaders = [String: String]()
        if  let headers = headers  {
            for  (headerName, headerValue) in headers  {
                allHeaders[headerName] = headerValue
            }
        }
        allHeaders["Content-Type"] = "text/plain"
        let options: [ClientRequest.Options] =
            [.method(method), .hostname(host), .port(8090), .path(path), .headers(allHeaders)]
        let req = HTTP.request(options, callback: callback)
        if let requestModifier = requestModifier {
            requestModifier(req)
        }
        req.end()
    }

    func expectation(_ index: Int) -> XCTestExpectation {
        let expectationDescription = "\(type(of: self))-\(index)"
        return self.expectation(description: expectationDescription)
    }

    func waitExpectation(timeout t: TimeInterval, handler: XCWaitCompletionHandler?) {
        self.waitForExpectations(timeout: t, handler: handler)
    }

    func perfReq(headers: [String: String]?, callback: @escaping ClientRequest.Callback) {
        performRequest(method: "get", host: "localhost", path: "/test", callback: callback, headers: headers, requestModifier: nil)
    }

    func perfReq(path: String, callback: @escaping ClientRequest.Callback) {
        performRequest(method: "get", host: "localhost", path: path, callback: callback, headers: nil, requestModifier: nil)
    }

    func perfReq(host: String, path: String, callback: @escaping ClientRequest.Callback) {
        performRequest(method: "get", host: host, path: path, callback: callback, headers: nil, requestModifier: nil)
    }
}
