import Foundation
import simd

public actor PDBParser {
    // MARK: - Records
    
    private struct PDBAtomLine {
        let line: Int
        let element: AtomElement
        let chainID: String
        let resID: Int
        let resType: Residue
        let position: simd_float3
    }
    
    protocol PDBSecondaryStructureLine {
        var line: Int { get }
        var initChainID: String { get }
        var initResID: Int { get }
        var finalChainID: String { get }
        var finalResID: Int { get }
        var underlyingType: SecondaryStructure { get }
    }
    
    private struct PDBHelixLine: PDBSecondaryStructureLine {
        let line: Int
        let initChainID: String
        let initResID: Int
        let finalChainID: String
        let finalResID: Int
        let underlyingType: SecondaryStructure = .helix
    }
    
    private struct PDBSheetLine: PDBSecondaryStructureLine {
        let line: Int
        let initChainID: String
        let initResID: Int
        let finalChainID: String
        let finalResID: Int
        let underlyingType: SecondaryStructure = .sheet
    }
    
    private struct PDBModelEndLine {
        let line: Int
    }
    
    private struct PDBSubunitEndLine {
        let line: Int
    }
    
    private struct PDBTitleLine {
        let line: Int
        let rawText: String
    }
    
    private struct PDBAuthorLine {
        let line: Int
        let rawText: String
    }
    
    // MARK: - Blocks
    
    private final class ParsedBlock {
        var pdbID: String?
        var titleRecords = [PDBTitleLine]()
        var authorRecords = [PDBAuthorLine]()
        var atomRecords = [PDBAtomLine]()
        var helixRecords = [PDBHelixLine]()
        var sheetRecords = [PDBSheetLine]()
        var modelEndRecord = [PDBModelEndLine]()
        var subunitEndRecords = [PDBSubunitEndLine]()
    }
    
    // MARK: - Models and subunits
    
    private class ParsedModel {
        let startLine: Int
        var endLine: Int
        var chains = [ParsedSubunit]()
        
        var atomPositions = [simd_float3]()
        var atomElements = [AtomElement]()
        var atomChainIDs = [ChainID]()
        var atomResidues = [Residue]()
        var atomSecondaryStructure = [SecondaryStructure]()
        
        init(startLine: Int, endLine: Int) {
            self.startLine = startLine
            self.endLine = endLine
        }
    }
    
    private class ParsedSubunit {
        let id = UUID()
        let isPartOfChain: Bool
        let startLine: Int
        let endLine: Int
        var atomCount: Int = 0
        
        init(startLine: Int, endLine: Int, isPartOfChain: Bool) {
            self.startLine = startLine
            self.endLine = endLine
            self.isPartOfChain = isPartOfChain
        }
    }
    
    // MARK: - Init
    
    public init() {}
    
    // MARK: - Parse file
    
    public func parsePDB(
        fileName: String,
        fileExtension: String,
        byteSize: Int?,
        rawText: String,
        progress: Progress,
        originalFileInfo: ProteinFileInfo? = nil
    ) throws -> ProteinFile {
        var parsedBlock = ParsedBlock()
        let rawLines = rawText.split(separator: "\n").map({ String($0) })
        
        // Parse all records
        for (index, line) in rawLines.enumerated() {
            parseLine(line: line, lineNumber: index, into: &parsedBlock)
        }
        
        // Parse models
        var models = [Protein]()
        var currentModel: ParsedModel?
        
        for (index, line) in rawLines.enumerated() {
            if line.starts(with: "MODEL") {
                currentModel = ParsedModel(startLine: index, endLine: index)
            } else if line.starts(with: "ENDMDL") {
                if let model = currentModel {
                    model.endLine = index
                    models.append(createProtein(from: model))
                    currentModel = nil
                }
            } else if line.starts(with: "ATOM") || line.starts(with: "HETATM") {
                if currentModel == nil {
                    currentModel = ParsedModel(startLine: index, endLine: index)
                }
                
                if let atomLine = parseAtomLine(line: line, lineNumber: index) {
                    currentModel?.atomPositions.append(atomLine.position)
                    currentModel?.atomElements.append(atomLine.element)
                    currentModel?.atomChainIDs.append(ChainID(string: atomLine.chainID) ?? .zero)
                    currentModel?.atomResidues.append(atomLine.resType)
                }
            }
        }
        
        // If no models were found, create a single model from all atoms
        if models.isEmpty {
            let model = ParsedModel(startLine: 0, endLine: rawLines.count - 1)
            for (index, line) in rawLines.enumerated() {
                if line.starts(with: "ATOM") || line.starts(with: "HETATM") {
                    if let atomLine = parseAtomLine(line: line, lineNumber: index) {
                        model.atomPositions.append(atomLine.position)
                        model.atomElements.append(atomLine.element)
                        model.atomChainIDs.append(ChainID(string: atomLine.chainID) ?? .zero)
                        model.atomResidues.append(atomLine.resType)
                    }
                }
            }
            models.append(createProtein(from: model))
        }
        
        // Update file info with parsed data
        var fileInfo = ProteinFileInfo(
            pdbID: originalFileInfo?.pdbID,
            description: originalFileInfo?.description,
            authors: originalFileInfo?.authors,
            sourceLines: originalFileInfo?.sourceLines
        )
        
        if fileInfo.pdbID == nil {
            fileInfo = ProteinFileInfo(
                pdbID: parsedBlock.pdbID,
                description: fileInfo.description,
                authors: fileInfo.authors,
                sourceLines: fileInfo.sourceLines
            )
        }
        
        return ProteinFile(
            fileType: .staticStructure,
            fileName: fileName,
            fileExtension: fileExtension,
            models: models,
            fileInfo: fileInfo,
            byteSize: byteSize
        )
    }
    
    // MARK: - Private methods
    
    private func parseLine(line: String, lineNumber: Int, into parsedBlock: inout ParsedBlock) {
        if line.starts(with: "HEADER") {
            parsedBlock.pdbID = String(line.dropFirst(62).trimmingCharacters(in: .whitespaces))
        } else if line.starts(with: "TITLE") {
            parsedBlock.titleRecords.append(PDBTitleLine(line: lineNumber, rawText: line))
        } else if line.starts(with: "AUTHOR") {
            parsedBlock.authorRecords.append(PDBAuthorLine(line: lineNumber, rawText: line))
        } else if line.starts(with: "ATOM") || line.starts(with: "HETATM") {
            if let atomLine = parseAtomLine(line: line, lineNumber: lineNumber) {
                parsedBlock.atomRecords.append(atomLine)
            }
        } else if line.starts(with: "HELIX") {
            if let helixLine = parseHelixLine(line: line, lineNumber: lineNumber) {
                parsedBlock.helixRecords.append(helixLine)
            }
        } else if line.starts(with: "SHEET") {
            if let sheetLine = parseSheetLine(line: line, lineNumber: lineNumber) {
                parsedBlock.sheetRecords.append(sheetLine)
            }
        } else if line.starts(with: "ENDMDL") {
            parsedBlock.modelEndRecord.append(PDBModelEndLine(line: lineNumber))
        } else if line.starts(with: "TER") {
            parsedBlock.subunitEndRecords.append(PDBSubunitEndLine(line: lineNumber))
        }
    }
    
    private func parseAtomLine(line: String, lineNumber: Int) -> PDBAtomLine? {
        guard line.count >= 54 else { return nil }
        
        let elementStartIndex = line.index(line.startIndex, offsetBy: 76)
        let elementEndIndex = line.index(line.startIndex, offsetBy: 78)
        let elementString = String(line[elementStartIndex..<elementEndIndex]).trimmingCharacters(in: .whitespaces)
        guard let element = AtomElement(string: elementString) else { return nil }
        
        let chainIDIndex = line.index(line.startIndex, offsetBy: 21)
        let chainID = String(line[chainIDIndex])
        
        let resIDStartIndex = line.index(line.startIndex, offsetBy: 22)
        let resIDEndIndex = line.index(line.startIndex, offsetBy: 26)
        let resIDString = String(line[resIDStartIndex..<resIDEndIndex]).trimmingCharacters(in: .whitespaces)
        guard let resID = Int(resIDString) else { return nil }
        
        let resTypeStartIndex = line.index(line.startIndex, offsetBy: 17)
        let resTypeEndIndex = line.index(line.startIndex, offsetBy: 20)
        let resTypeString = String(line[resTypeStartIndex..<resTypeEndIndex]).trimmingCharacters(in: .whitespaces)
        guard let resType = Residue(string: resTypeString) else { return nil }
        
        let xStartIndex = line.index(line.startIndex, offsetBy: 30)
        let xEndIndex = line.index(line.startIndex, offsetBy: 38)
        let yStartIndex = line.index(line.startIndex, offsetBy: 38)
        let yEndIndex = line.index(line.startIndex, offsetBy: 46)
        let zStartIndex = line.index(line.startIndex, offsetBy: 46)
        let zEndIndex = line.index(line.startIndex, offsetBy: 54)
        
        let xString = String(line[xStartIndex..<xEndIndex]).trimmingCharacters(in: .whitespaces)
        let yString = String(line[yStartIndex..<yEndIndex]).trimmingCharacters(in: .whitespaces)
        let zString = String(line[zStartIndex..<zEndIndex]).trimmingCharacters(in: .whitespaces)
        
        guard let x = Float(xString),
              let y = Float(yString),
              let z = Float(zString) else { return nil }
        
        return PDBAtomLine(
            line: lineNumber,
            element: element,
            chainID: chainID,
            resID: resID,
            resType: resType,
            position: simd_float3(x, y, z)
        )
    }
    
    private func parseHelixLine(line: String, lineNumber: Int) -> PDBHelixLine? {
        guard line.count >= 71 else { return nil }
        
        let initChainIDIndex = line.index(line.startIndex, offsetBy: 19)
        let initChainID = String(line[initChainIDIndex])
        
        let initResIDStartIndex = line.index(line.startIndex, offsetBy: 21)
        let initResIDEndIndex = line.index(line.startIndex, offsetBy: 25)
        let initResIDString = String(line[initResIDStartIndex..<initResIDEndIndex]).trimmingCharacters(in: .whitespaces)
        
        let finalChainIDIndex = line.index(line.startIndex, offsetBy: 31)
        let finalChainID = String(line[finalChainIDIndex])
        
        let finalResIDStartIndex = line.index(line.startIndex, offsetBy: 33)
        let finalResIDEndIndex = line.index(line.startIndex, offsetBy: 37)
        let finalResIDString = String(line[finalResIDStartIndex..<finalResIDEndIndex]).trimmingCharacters(in: .whitespaces)
        
        guard let initResID = Int(initResIDString),
              let finalResID = Int(finalResIDString) else { return nil }
        
        return PDBHelixLine(
            line: lineNumber,
            initChainID: initChainID,
            initResID: initResID,
            finalChainID: finalChainID,
            finalResID: finalResID
        )
    }
    
    private func parseSheetLine(line: String, lineNumber: Int) -> PDBSheetLine? {
        guard line.count >= 71 else { return nil }
        
        let initChainIDIndex = line.index(line.startIndex, offsetBy: 21)
        let initChainID = String(line[initChainIDIndex])
        
        let initResIDStartIndex = line.index(line.startIndex, offsetBy: 22)
        let initResIDEndIndex = line.index(line.startIndex, offsetBy: 26)
        let initResIDString = String(line[initResIDStartIndex..<initResIDEndIndex]).trimmingCharacters(in: .whitespaces)
        
        let finalChainIDIndex = line.index(line.startIndex, offsetBy: 32)
        let finalChainID = String(line[finalChainIDIndex])
        
        let finalResIDStartIndex = line.index(line.startIndex, offsetBy: 33)
        let finalResIDEndIndex = line.index(line.startIndex, offsetBy: 37)
        let finalResIDString = String(line[finalResIDStartIndex..<finalResIDEndIndex]).trimmingCharacters(in: .whitespaces)
        
        guard let initResID = Int(initResIDString),
              let finalResID = Int(finalResIDString) else { return nil }
        
        return PDBSheetLine(
            line: lineNumber,
            initChainID: initChainID,
            initResID: initResID,
            finalChainID: finalChainID,
            finalResID: finalResID
        )
    }
    
    private func createProtein(from model: ParsedModel) -> Protein {
        let elementComposition = ProteinElementComposition(elements: model.atomElements)
        let chainComposition = ProteinChainComposition(chainIDs: model.atomChainIDs)
        let residueComposition = ProteinResidueComposition(residues: model.atomResidues)
        
        return Protein(
            configurationCount: 1,
            configurationEnergies: nil,
            atoms: ContiguousArray(model.atomPositions),
            elementComposition: elementComposition,
            atomElements: model.atomElements,
            chainComposition: chainComposition,
            atomChainIDs: model.atomChainIDs,
            residueComposition: residueComposition,
            atomResidues: model.atomResidues,
            atomSecondaryStructure: model.atomSecondaryStructure
        )
    }
} 