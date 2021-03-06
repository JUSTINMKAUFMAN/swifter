//
//  DemoServer.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

import Foundation


public func demoServer(_ publicDir: String) -> HttpServer {
    
    print(publicDir)
    
    let server = HttpServer()
    
    server["/public/:path"] = shareFilesFromDirectory(publicDir)

    server["/files/:path"] = directoryBrowser("/")

    server["/"] = scopes {
        html {
            body {
                ul(server.routes) { service in
                    li {
                        a { href = service; inner = service }
                    }
                }
            }
        }
    }
    
    server["/magic"] = { .ok(.html("You asked for " + $0.path)) }
    
    server["/test/:param1/:param2"] = { r in
        scopes {
            html {
                body {
                    h3 { inner = "Address: \(r.address ?? "unknown")" }
                    h3 { inner = "Url: \(r.path)" }
                    h3 { inner = "Method: \(r.method)" }
                    
                    h3 { inner = "Query:" }
                    
                    table(r.queryParams) { param in
                        tr {
                            td { inner = param.0 }
                            td { inner = param.1 }
                        }
                    }
                    
                    h3 { inner = "Headers:" }
                    
                    table(r.headers) { header in
                        tr {
                            td { inner = header.0 }
                            td { inner = header.1 }
                        }
                    }
                    
                    h3 { inner = "Route params:" }
                    
                    table(r.params) { param in
                        tr {
                            td { inner = param.0 }
                            td { inner = param.1 }
                        }
                    }
                }
            }
        }(r)
    }
    
    server.GET["/upload"] = scopes {
        html {
            body {
                form {
                    method = "POST"
                    action = "/upload"
                    enctype = "multipart/form-data"
                    
                    input { name = "my_file1"; type = "file" }
                    input { name = "my_file2"; type = "file" }
                    input { name = "my_file3"; type = "file" }
                    
                    button {
                        type = "submit"
                        inner = "Upload"
                    }
                }
            }
        }
    }
    
    server.POST["/upload"] = { r in
        var response = ""
        for multipart in r.parseMultiPartFormData() {
            guard let name = multipart.name, let fileName = multipart.fileName else { continue }
            response += "Name: \(name) File name: \(fileName) Size: \(multipart.body.count)<br>"
        }
        return HttpResponse.ok(.html(response))
    }

    server.GET["/upload/logo"] = { r in
        guard let resourceURL = Bundle.main.resourceURL else {
            return .notFound
        }

        let logoURL = resourceURL.appendingPathComponent("logo.png")
        guard let exists = try? logoURL.path.exists(), true == exists else {
            return .notFound
        }

        guard let url = URL(string: "http://127.0.0.1:9080/upload/logo"), let body = try? Data(contentsOf: logoURL) else {
            return .notFound
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        guard let data = try? NSURLConnection.sendSynchronousRequest(request, returning: nil) else {
            return .badRequest(.html("Failed to send data"))
        }
        return .raw(200, "OK", [:], { writter in
            try writter.write(data)
        })
    }

    server.filePreprocess = true
    server.POST["/upload/logo"] = { r in
        guard let path = r.tempFile else {
            return .badRequest(.html("no file"))
        }
        guard let file = try? path.openForReading() else {
            return .notFound
        }
        return .raw(200, "OK", [:], { writter in
            try writter.write(file)
        })
    }
    
    server.GET["/login"] = scopes {
        html {
            head {
                script { src = "http://cdn.staticfile.org/jquery/2.1.4/jquery.min.js" }
                stylesheet { href = "http://cdn.staticfile.org/twitter-bootstrap/3.3.0/css/bootstrap.min.css" }
            }
            body {
                h3 { inner = "Sign In" }
                
                form {
                    method = "POST"
                    action = "/login"
                    
                    fieldset {
                        input { placeholder = "E-mail"; name = "email"; type = "email"; autofocus = "" }
                        input { placeholder = "Password"; name = "password"; type = "password"; autofocus = "" }
                        a {
                            href = "/login"
                            button {
                                type = "submit"
                                inner = "Login"
                            }
                        }
                    }
                    
                }
                javascript {
                    src = "http://cdn.staticfile.org/twitter-bootstrap/3.3.0/js/bootstrap.min.js"
                }
            }
        }
    }
    
    server.POST["/login"] = { r in
        let formFields = r.parseUrlencodedForm()
        return HttpResponse.ok(.html(formFields.map({ "\($0.0) = \($0.1)" }).joined(separator: "<br>")))
    }
    
    server["/demo"] = scopes {
        html {
            body {
                center {
                    h2 { inner = "Hello Swift" }
                    img { src = "https://devimages.apple.com.edgekey.net/swift/images/swift-hero_2x.png" }
                }
            }
        }
    }
    
    server["/raw"] = { r in
        return HttpResponse.raw(200, "OK", ["XXX-Custom-Header": "value"], { try $0.write([UInt8]("test".utf8)) })
    }
    
    server["/redirect"] = { r in
        return .movedPermanently("http://www.google.com")
    }

    server["/long"] = { r in
        var longResponse = ""
        for k in 0..<1000 { longResponse += "(\(k)),->" }
        return .ok(.html(longResponse))
    }
    
    server["/wildcard/*/test/*/:param"] = { r in
        return .ok(.html(r.path))
    }
    
    server["/stream"] = { r in
        return HttpResponse.raw(200, "OK", nil, { w in
            for i in 0...100 {
                try w.write([UInt8]("[chunk \(i)]".utf8))
            }
        })
    }

    server["/websocket-echo"] = websocket(text: { (session, text) in
        session.writeText(text)
    }, binary: { (session, binary) in
        session.writeBinary(binary)
    }, pong: { (session, pong) in
        // Got a pong frame
    }, connected: { (session) in
        // New client connected
    }, disconnected: { (session) in
        // Client disconnected
    })
    
    server.notFoundHandler = { r in
        return .movedPermanently("https://github.com/404")
    }
    
    server.middleware.append { r in
        print("Middleware: \(r.address ?? "unknown address") -> \(r.method) -> \(r.path)")
        return nil
    }
    
    return server
}
    
