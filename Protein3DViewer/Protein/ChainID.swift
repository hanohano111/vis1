import Foundation

public struct ChainID: Hashable {
    public let rawValue: String
    
    public static let zero = ChainID(rawValue: "A")
    
    public init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        self.rawValue = trimmed
    }
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
} 