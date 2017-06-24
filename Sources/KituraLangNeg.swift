import Foundation
import Kitura
import LoggerAPI

public class LanguageNegotiation: RouterMiddleware {

    public struct NegMatch {
        public let lang: String
        public let method: NegMethod
        public let quality: Float

        init(lang: String, method: NegMethod, quality: Float = 1.0) {
            self.lang = lang
            self.method = method
            self.quality = quality
        }
    }

    public enum NegMethod {
        // Matched on a subdomain (eg, en.example.com)
        case Subdomain
        // Matched on a path prefix (eg, /en/rest/of/path)
        case PathPrefix
        // Matched on the Accept-Language header
        case Header
        // Used when all negotiation attempts failed and we fell back to the
        // first lang in the langs parameter
        case Default
        // Negotiation completely failed.
        case Failure
        // We haven't attempted negotiation yet.
//        case Unattempted
    }

    public struct Methods: OptionSet {
        public let rawValue: UInt8
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        // Attempt negotiation with the first subdomain (eg, en.example.com)
        static let subdomain = Methods(rawValue: 1 << 0)
        // Attempt negotiation with the first path segment (eg,
        // example.com/en/hello)
        static let pathPrefix = Methods(rawValue: 1 << 1)
        // Attempt negoitation with the Accept-Language response header
        static let header = Methods(rawValue: 1 << 2)
    }

    public struct Options: OptionSet {
        public let rawValue: UInt8
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        // Don't send Content-Language header
        static let noContentLanguage = Options(rawValue: 1 << 0)
        // Don't send Vary header if Methods.header is active and we didn't
        // match on another method
        static let noVary = Options(rawValue: 1 << 1)
        // Do a 307 redirect to the same path with a subdomain or path prefix
        // corresponding to the matched langcode iff we matched on the
        // Accept-Language header but no other method. Note that if this
        // redirection happens, no Content-Language header is sent.
        static let redirectOnHeaderMatch = Options(rawValue: 1 << 2)
        // Send a 406 status code if we can't satisfy an Accept-Language request
        // (default behavior is to just select the first langcode
        static let notAcceptableOnHeaderMatchFail = Options(rawValue: 1 << 3)
    }

    enum NegMethodError: Error {
        // Initialized with an empty langs array. That's useless.
        case InitWithNoLangs
        // Initialized with no methods defined. That's useless too.
        case InitWithNoMethods
        // Trying to use both subdomain and path prefix methods.
        case SubdomainAndPathPrefix
        // Using the redirectOnHeaderMatch option with only the header method.
        // We don't know what we should redirect to.
        case RedirectWhere
    }

    let methods: Methods
    let options: Options
    let langs: [String]
    lazy var subdomainPattern: NSRegularExpression = self.computeSubdomainPattern()
    lazy var acceptLanguagePattern: NSRegularExpression = self.computeAcceptLanguagePattern()
    lazy var routerPaths: String = self.computeRouterPaths()

    public init(_ langs: [String], methods: Methods, options: Options = []) throws {
        guard langs.count > 0 else {
            throw NegMethodError.InitWithNoLangs
        }
        guard methods.rawValue != 0 else {
            throw NegMethodError.InitWithNoMethods
        }
        // @todo probably better way to check both of the below
        guard !(methods.contains(.pathPrefix) && methods.contains(.subdomain)) else {
            throw NegMethodError.SubdomainAndPathPrefix
        }
        guard !options.contains(.redirectOnHeaderMatch) || (methods.contains(.pathPrefix) || methods.contains(.subdomain)) else {
            throw NegMethodError.RedirectWhere
        }
        self.langs = langs
        self.methods = methods
        self.options = options
    }

    public func handle(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        defer {
            next()
        }

        var match: NegMatch?

        if methods.contains(.pathPrefix) {
            if let prefix = request.parameters["0"] {
                match = NegMatch(lang: prefix, method: .PathPrefix)
            }
            else {
                Log.verbose("LangNeg: Prefix matching failed; prefix not found or not acceptable")
            }
        }
        else if methods.contains(.subdomain) {
            if let subMatch = subdomainPattern.firstMatch(in: request.domain, options: [], range: NSRange(location: 0, length: request.domain.utf16.count)) {
                let sub = request.domain.substring(to: request.domain.index(request.domain.startIndex, offsetBy: subMatch.rangeAt(1).length))
                match = NegMatch(lang: sub, method: .Subdomain)

            }
            else {
                Log.verbose("LangNeg: Subdomain matching failed; subdomain not found or not acceptable")
            }
        }

        if match == nil, methods.contains(.header) {
            if !options.contains(.noVary) {
                response.headers["Vary"] = "Accept-Language"
            }

            if let acceptHeader = request.headers["Accept-Language"] {
                match = attemptHeaderMatch(acceptHeader: acceptHeader)
            }

            if match == nil {
                Log.verbose("LangNeg: Accept-Language matching failed.")
                if options.contains(.notAcceptableOnHeaderMatchFail) {
                    request.userInfo["LangNeg"] = NegMatch(lang: "", method: .Failure)
                    try! response.status(.notAcceptable).end()
                }
            }
            else if options.contains(.redirectOnHeaderMatch) {
                var url = URLComponents(string: request.urlURL.absoluteString)!
                if methods.contains(.pathPrefix) {
                    url.path = "/" + match!.lang + url.path
                }
                else if methods.contains(.subdomain) {
                    url.host = match!.lang + "." + url.host!
                }
                let destination = url.string!
                Log.verbose("LangNeg: Redirecting on Accept-Language match to \(destination)")
                try! response.redirect(destination, status: .temporaryRedirect)
            }
        }

        // After all that, did we still fail to find a match?
        if match == nil {
            match = NegMatch(lang: langs.first!, method: .Default, quality: 0.0)
        }

        if !options.contains(.noContentLanguage) {
            response.headers["Content-Language"] = match!.lang
        }

        request.userInfo["LangNeg"] = match

    }

    func attemptHeaderMatch(acceptHeader: String) -> NegMatch? {
        var currentBestMatch: NegMatch?

        for acceptable in acceptHeader.components(separatedBy: ",") {
            let acceptableCount = acceptable.utf16.count
            guard let alMatch = acceptLanguagePattern.firstMatch(in: acceptable, options: [], range: NSRange(location: 0, length: acceptableCount)) else {
                // This code seems to be seriously malformed.
                continue
            }

            // Extract the langcode
            let langcodeRange = alMatch.rangeAt(1)
            let start = String.UTF16Index(langcodeRange.location)
            let end = String.UTF16Index(langcodeRange.location + langcodeRange.length)
            var langcode = String(acceptable.utf16[start..<end])!
            if langcode == "*" {
                langcode = langs.first!
            }

            let quality: Float?
            let qualityRange = alMatch.rangeAt(2)
            if qualityRange.location == NSNotFound {
                // If there's no quality specified, use 1.
                quality = 1.0
            }
            else {
                // Extract the quality.
                let start = String.UTF16Index(qualityRange.location)
                let end = String.UTF16Index(qualityRange.location + qualityRange.length)
                quality = Float(String(acceptable.utf16[start..<end])!)
                // "all languages which are assigned a quality factor greater
                // than 0 are acceptable," so treat a best match with a quality
                // of 0 as no match at all. (If quality was so malformed that we
                // couldn't parse it, treat that as zero.)
                if quality == nil || quality == 0 {
                    continue;
                }
            }

            if langs.contains(langcode) && (currentBestMatch == nil || quality! > currentBestMatch!.quality) {
                currentBestMatch = NegMatch(lang: langcode, method: .Header, quality: quality!)
                if quality! == 1.0 {
                    // We can't do better than this, so stop iterating.
                    return currentBestMatch
                }
            }
        }

        return currentBestMatch
    }

    func computeSubdomainPattern() -> NSRegularExpression {
        let langcodes = langs.joined(separator: "|")
        return try! NSRegularExpression(pattern: "^(" + langcodes + ")\\.", options: [])
    }

    func computeAcceptLanguagePattern() -> NSRegularExpression {
        return try! NSRegularExpression(pattern: "([a-zA-Z-]+|\\*)(?:.+?([\\d\\.]+))?", options: [])
    }

    func computeRouterPaths() -> String {
        // For some reason (Kitura bug?) the unbalanced parentheses are correct
        // here.
        return "/(" + langs.joined(separator: "|") + "))"
    }
}
