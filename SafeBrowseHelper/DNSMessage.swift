import Foundation

// DNS wire-format parser and response builder.
// Implements the minimal subset of RFC 1035 needed for our use case.
enum DNSMessage {

    // MARK: - Query parsing

    /// Extract the queried domain name (QNAME) from the first question in a DNS packet.
    static func extractQueryName(from data: Data) -> String? {
        guard data.count >= 12 else { return nil }

        var offset = 12 // skip 12-byte header
        var labels: [String] = []

        while offset < data.count {
            let length = Int(data[offset])

            // Null terminator
            if length == 0 { break }

            // Compression pointer (top two bits = 11)
            if (length & 0xC0) == 0xC0 {
                guard offset + 1 < data.count else { return nil }
                let ptr = ((length & 0x3F) << 8) | Int(data[offset + 1])
                guard ptr < data.count else { return nil }
                var pOffset = ptr
                while pOffset < data.count {
                    let pLen = Int(data[pOffset])
                    if pLen == 0 { break }
                    pOffset += 1
                    guard pOffset + pLen <= data.count else { return nil }
                    if let label = String(bytes: data[pOffset ..< pOffset + pLen], encoding: .utf8) {
                        labels.append(label)
                    }
                    pOffset += pLen
                }
                break
            }

            offset += 1
            guard offset + length <= data.count else { return nil }
            if let label = String(bytes: data[offset ..< offset + length], encoding: .utf8) {
                labels.append(label)
            }
            offset += length
        }

        return labels.isEmpty ? nil : labels.joined(separator: ".").lowercased()
    }

    /// Returns true when the QR bit is 0 (i.e. the packet is a query, not a response).
    static func isQuery(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        return (data[2] & 0x80) == 0
    }

    // MARK: - Response building

    /// Build a minimal NXDOMAIN response that mirrors the query's header.
    ///
    /// Layout of bytes 2–3 in the response:
    ///   Byte 2: QR=1  OPCODE=0000  AA=0  TC=0  RD=<copied>
    ///   Byte 3: RA=1  Z=000  RCODE=0011 (NXDOMAIN)
    static func buildNXDOMAINResponse(for query: Data) -> Data {
        guard query.count >= 12 else { return query }
        var response = query

        let rd = query[2] & 0x01          // copy Recursion Desired bit
        response[2] = 0x80 | rd           // QR=1, OPCODE=0, AA=0, TC=0, RD
        response[3] = 0x83                 // RA=1, Z=0, RCODE=3 (NXDOMAIN)

        // Zero ANCOUNT, NSCOUNT, ARCOUNT
        response[6] = 0; response[7] = 0
        response[8] = 0; response[9] = 0
        response[10] = 0; response[11] = 0

        return response
    }
}
