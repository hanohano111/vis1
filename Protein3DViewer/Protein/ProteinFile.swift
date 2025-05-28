import Foundation

public struct ProteinFile {
    public let fileType: FileType
    public let fileName: String
    public let fileExtension: String
    public let models: [Protein]
    public let fileInfo: ProteinFileInfo
    public let byteSize: Int?
    
    public init(
        fileType: FileType,
        fileName: String,
        fileExtension: String,
        models: [Protein],
        fileInfo: ProteinFileInfo,
        byteSize: Int?
    ) {
        self.fileType = fileType
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.models = models
        self.fileInfo = fileInfo
        self.byteSize = byteSize
    }
}

public struct ProteinFileInfo {
    public let pdbID: String?
    public let description: String?
    public let authors: String?
    public let sourceLines: String?
    
    public init(
        pdbID: String?,
        description: String?,
        authors: String?,
        sourceLines: String?
    ) {
        self.pdbID = pdbID
        self.description = description
        self.authors = authors
        self.sourceLines = sourceLines
    }
}

public enum FileType {
    case staticStructure
    case trajectory
} 