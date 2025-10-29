//
//  VoiceInkHTTPServer.swift
//  VoiceInk-ios
//
//  HTTP server for receiving audio uploads from ESP32 devices
//

import Foundation
import Network
import OSLog
import SwiftData

@MainActor
class VoiceInkHTTPServer: ObservableObject {
    private let logger = Logger(subsystem: "com.voiceink", category: "HTTPServer")
    private var listener: NWListener?
    private let port: UInt16
    private let recordingManager: RecordingManager
    private let modelContainer: ModelContainer

    @Published var isRunning = false
    @Published var serverAddress: String = ""

    init(port: UInt16 = 8080, recordingManager: RecordingManager, modelContainer: ModelContainer) {
        self.port = port
        self.recordingManager = recordingManager
        self.modelContainer = modelContainer
    }

    func start() {
        guard listener == nil else {
            logger.warning("Server already running")
            return
        }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.acceptLocalOnly = true // Security: only accept local network connections

            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleStateChange(state)
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }

            listener.start(queue: .main)
            logger.info("HTTP Server starting on port \(self.port)")

        } catch {
            logger.error("Failed to start server: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        serverAddress = ""
        logger.info("HTTP Server stopped")
    }

    private func handleStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            if let port = listener?.port {
                serverAddress = "http://\(getLocalIPAddress()):\(port)"
                logger.info("Server ready at \(self.serverAddress)")
            }
        case .failed(let error):
            logger.error("Server failed: \(error.localizedDescription)")
            isRunning = false
            stop()
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 50 * 1024 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                if let data = data, !data.isEmpty {
                    self?.handleRequest(data: data, connection: connection)
                }

                if isComplete {
                    connection.cancel()
                }
            }
        }
    }

    private func handleRequest(data: Data, connection: NWConnection) {
        // Parse HTTP request
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }

        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }

        let components = requestLine.components(separatedBy: " ")
        guard components.count >= 2 else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }

        let method = components[0]
        let path = components[1]

        logger.info("Received \(method) \(path)")

        // Route handling
        if method == "POST" && path == "/api/upload/audio" {
            handleAudioUpload(data: data, connection: connection)
        } else if method == "GET" && path == "/" {
            sendResponse(connection: connection, statusCode: 200, body: "VoiceInk Server Running")
        } else if method == "GET" && path == "/health" {
            sendResponse(connection: connection, statusCode: 200, body: "OK")
        } else {
            sendResponse(connection: connection, statusCode: 404, body: "Not Found")
        }
    }

    private func handleAudioUpload(data: Data, connection: NWConnection) {
        // Find the double CRLF that separates headers from body
        guard let headerEndRange = data.range(of: "\r\n\r\n".data(using: .utf8)!) else {
            sendResponse(connection: connection, statusCode: 400, body: "Invalid request format")
            return
        }

        // Extract audio data (everything after headers)
        let audioData = data.suffix(from: headerEndRange.upperBound)

        // Validate minimum audio file size (at least 1KB)
        guard audioData.count > 1024 else {
            sendResponse(connection: connection, statusCode: 400, body: "Audio data too small")
            return
        }

        // Save audio file
        let timestamp = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "esp32_\(formatter.string(from: timestamp)).wav"

        do {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let recordingsPath = documentsPath.appendingPathComponent("Recordings", isDirectory: true)

            // Create Recordings directory if it doesn't exist
            try FileManager.default.createDirectory(at: recordingsPath, withIntermediateDirectories: true)

            let fileURL = recordingsPath.appendingPathComponent(filename)
            try audioData.write(to: fileURL)

            logger.info("Saved audio file: \(filename) (\(audioData.count) bytes)")

            // Trigger transcription using existing pipeline
            Task {
                let modelContext = ModelContext(self.modelContainer)
                await self.recordingManager.processUploadedAudio(fileURL: fileURL, timestamp: timestamp, modelContext: modelContext)
            }

            sendResponse(connection: connection, statusCode: 200, body: "Upload successful")

        } catch {
            logger.error("Failed to save audio: \(error.localizedDescription)")
            sendResponse(connection: connection, statusCode: 500, body: "Failed to save audio")
        }
    }

    private func sendResponse(connection: NWConnection, statusCode: Int, body: String) {
        let statusText = HTTPStatus.text(for: statusCode)
        let bodyData = body.data(using: .utf8) ?? Data()

        let response = """
            HTTP/1.1 \(statusCode) \(statusText)\r
            Content-Type: text/plain\r
            Content-Length: \(bodyData.count)\r
            Connection: close\r
            \r
            \(body)
            """.data(using: .utf8) ?? Data()

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func getLocalIPAddress() -> String {
        var address = "localhost"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return address }
        guard let firstAddr = ifaddr else { return address }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) {
                if addr.sa_family == UInt8(AF_INET) || addr.sa_family == UInt8(AF_INET6) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST) == 0 {
                        address = String(cString: hostname)
                        // Prefer IPv4 addresses
                        if addr.sa_family == UInt8(AF_INET) {
                            break
                        }
                    }
                }
            }
        }

        freeifaddrs(ifaddr)
        return address
    }
}

// HTTP Status code helper
struct HTTPStatus {
    static func text(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }
}
