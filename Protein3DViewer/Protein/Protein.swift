import Foundation
import simd

public struct Protein {
    public let configurationCount: Int
    public let configurationEnergies: [Float]?
    public let atoms: ContiguousArray<simd_float3>
    public let elementComposition: ProteinElementComposition
    public let atomElements: [AtomElement]
    public let chainComposition: ProteinChainComposition
    public let atomChainIDs: [ChainID]?
    public let residueComposition: ProteinResidueComposition
    public let atomResidues: [Residue]?
    public let atomSecondaryStructure: [SecondaryStructure]?
    
    public init(
        configurationCount: Int,
        configurationEnergies: [Float]?,
        atoms: ContiguousArray<simd_float3>,
        elementComposition: ProteinElementComposition,
        atomElements: [AtomElement],
        chainComposition: ProteinChainComposition,
        atomChainIDs: [ChainID]?,
        residueComposition: ProteinResidueComposition,
        atomResidues: [Residue]?,
        atomSecondaryStructure: [SecondaryStructure]?
    ) {
        self.configurationCount = configurationCount
        self.configurationEnergies = configurationEnergies
        self.atoms = atoms
        self.elementComposition = elementComposition
        self.atomElements = atomElements
        self.chainComposition = chainComposition
        self.atomChainIDs = atomChainIDs
        self.residueComposition = residueComposition
        self.atomResidues = atomResidues
        self.atomSecondaryStructure = atomSecondaryStructure
    }
}

public struct ProteinElementComposition {
    public let elements: [AtomElement]
    
    public init(elements: [AtomElement]) {
        self.elements = elements
    }
}

public struct ProteinChainComposition {
    public let chainIDs: [ChainID]?
    
    public init(chainIDs: [ChainID]?) {
        self.chainIDs = chainIDs
    }
}

public struct ProteinResidueComposition {
    public let residues: [Residue]?
    
    public init(residues: [Residue]?) {
        self.residues = residues
    }
} 