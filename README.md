# Kitura Language Negotiation

Kitura Language Negotiation is [Kitura](http://www.kitura.io) middleware to help your site provide responses to clients in multiple languages.

Kitura LangNeg can use a variety of methods to determine what language the user is requesting content in:

* The subdomain of the user's request, eg `http://en.example.org/`, `http://de.example.org/`, etc
* The subpath of the user's request, eg `http://example.org/en/hello`, `http://example.org/de/hello`, etc
* The Accept-Language HTTP header that the user-agent sent, if any

You can also redirect the user to a URL using one of the other methods if only the Accept-Language header method is triggered; eg, redirect someone requesting `http://example.org/hello` with an Accept-Language header with a value of "de" to "http://example.org/de/hello" (recommended for improved cacheablilty and SEO).

## Usage

Aside from the documentation below, please have a look at my [Kitura i18n Sample](https://github.com/NocturnalSolutions/Kitura-i18nSample) project which uses Kitura Language Negotiation along with [Kitura Translation](https://github.com/NocturnalSolutions/Kitura-Translation) to demonstrate a site with basic i18n (internationalization) features.

The example below will use the subdomain and header language negotiation methods; the user will be redirected to a URL with the appropriate subdomian if only the header method is triggered. (Note that when testing subdomains, you need to have those subdomains set up elsewhere; adding them to your hosts file is probably the easiest way to do so locally.)

```swift
import Kitura
import KituraLangNeg

let router = Router()
let ln = try! LanguageNegotiation(["en", "ja", "zh-hans", "es"], methods: [.subdomain, .header], options: [.redirectOnHeaderMatch])

router.all(middleware: ln)
router.all("/hello") { request, response, next in
    defer {
        next()
    }

    guard let negMatch = request.userInfo["LangNeg"] as? LanguageNegotiation.NegMatch else {
        // Something went horribly wrong
        return
    }

    switch negMatch.lang {
    case "en":
        response.send("Hello!\n")
    case "ja":
        response.send("こんにちは！\n")
    case "zh-hans":
        response.send("你好！\n")
    case "es":
        response.send("¡Hola!\n")
    default:
        response.send("This should never have happened.\n")
    }
}

Kitura.addHTTPServer(onPort: 8080, with: router)
Kitura.run()

```

Now, let's test. First, I've added the following to my local computer's hosts file:

```
127.0.0.1	en.localhost
127.0.0.1	ja.localhost
127.0.0.1	es.localhost
127.0.0.1	zh-hans.localhost
```

So now I can do:

```
> curl es.localhost:8080/hello
¡Hola!

> curl localhost:8080/hello -H "Accept-Language: ja" -I
HTTP/1.1 307 Temporary Redirect
Date: Sat, 24 Jun 2017 01:02:10 GMT
Location: http://ja.localhost:8080/hello
Content-Length: 0
Vary: Accept-Language
...

> curl ja.localhost:8080/hello
こんにちは！
```

Using the path prefix method is a bit more difficult since you need to use subrouters, but on the other hand, no domain name configuration silliness is necessary.

```swift
let subrouter = Router()
subrouter.all("/hello") { request, response, next in
  // As above
}

let ln = try! LanguageNegotiation(["en", "ja", "zh-hans", "es"], methods: [.pathPrefix])
let router = Router()
router.all(ln.routerPaths, allowPartialMatch: true, middleware: [ln, subrouter])

Kitura.addHTTPServer(onPort: 8080, with: router)
Kitura.run()
```

Now, to test:

```
> curl localhost:8080/en/hello
Hello!

> curl localhost:8080/zh-hans/hello
你好！
```

## Rough todo list

- Moar comments, documentation, and code standards adherence!
