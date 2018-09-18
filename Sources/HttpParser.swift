//
//  HttpParser.swift
//  Swifter
// 
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

import Foundation

enum HttpParserError: Error {
    case InvalidStatusLine(String)
}

public class HttpParser {
    
    public init() { }
    
    public func readHttpRequest(_ socket: Socket) throws -> HttpRequest {
        let statusLine = try socket.readLine()
        let statusLineTokens = statusLine.components(separatedBy: " ")
        if statusLineTokens.count < 3 {
            throw HttpParserError.InvalidStatusLine(statusLine)
        }
        let request = HttpRequest()
        request.method = statusLineTokens[0]
        request.path = statusLineTokens[1]
        request.queryParams = extractQueryParams(request.path)
        request.headers = try readHeaders(socket)
        if let contentLength = request.headers["content-length"], let contentLengthValue = Int(contentLength) {
            request.body = try readBody(socket, size: contentLengthValue)
        }
        return request
    }
    
    private func extractQueryParams(_ url: String) -> [(String, String)] {
        guard let questionMark = url.index(of: "?") else {
            return []
        }
        let queryStart = url.index(after: questionMark)
        guard url.endIndex > queryStart else {
            return []
        }
        let query = String(url[queryStart..<url.endIndex])
        return query.components(separatedBy: "&")
            .reduce([(String, String)]()) { (c, s) -> [(String, String)] in
                guard let nameEndIndex = s.index(of: "=") else {
                    return c
                }
                guard let name = String(s[s.startIndex..<nameEndIndex]).removingPercentEncoding else {
                    return c
                }
                let valueStartIndex = s.index(nameEndIndex, offsetBy: 1)
                guard valueStartIndex < s.endIndex else {
                    return c + [(name, "")]
                }
                guard let value = String(s[valueStartIndex..<s.endIndex]).removingPercentEncoding else {
                    return c + [(name, "")]
                }
                return c + [(name, value)]
        }
    }

    public func readContent(_ socket: Socket, request: HttpRequest, filePreprocess: Bool) throws {
        guard let contentType = request.headers["content-type"],
            let contentLength = request.headers["content-length"],
            let contentLengthValue = Int(contentLength) else {
                return
        }
        let isFileUpload = contentType == "application/octet-stream"
        if isFileUpload && filePreprocess {
            request.tempFile = try readFile(socket, length: contentLengthValue)
        }
        else {
            request.body = try readBody(socket, size: contentLengthValue)
        }
    }

    private let kBufferLength = 1024

    private func readFile(_ socket: Socket, length: Int) throws -> String {
        var offset = 0
        let filePath = NSTemporaryDirectory() + "/" + NSUUID().uuidString
        let file = try filePath.openNewForWriting()

        while offset < length {
            let length = offset + kBufferLength < length ? kBufferLength : length - offset
            let buffer = try socket.read(length: length)
            try file.write(buffer)
            offset += buffer.count
        }
        file.close()
        return filePath
    }
    
    private func readBody(_ socket: Socket, size: Int) throws -> [UInt8] {
        var body = [UInt8]()

        // Old approach read one byte at a time
        // for _ in 0..<size { body.append(try socket.read()) }

        var offset = 0
        while offset < size {
            let length = offset + kBufferLength < size ? kBufferLength : size - offset
            let buffer = try socket.read(length: length)
            body.append(contentsOf: buffer)
            offset += buffer.count
        }

        return body
    }
    
    private func readHeaders(_ socket: Socket) throws -> [String: String] {
        var headers = [String: String]()
        while case let headerLine = try socket.readLine() , !headerLine.isEmpty {
            let headerTokens = headerLine.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            if let name = headerTokens.first, let value = headerTokens.last {
                headers[name.lowercased()] = value.trimmingCharacters(in: .whitespaces)
            }
        }
        return headers
    }
    
    func supportsKeepAlive(_ headers: [String: String]) -> Bool {
        if let value = headers["connection"] {
            return "keep-alive" == value.trimmingCharacters(in: .whitespaces)
        }
        return false
    }
}
