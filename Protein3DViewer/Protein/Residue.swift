import Foundation

public enum Residue: String, CaseIterable {
    case alanine = "ALA"
    case arginine = "ARG"
    case asparagine = "ASN"
    case asparticAcid = "ASP"
    case cysteine = "CYS"
    case glutamicAcid = "GLU"
    case glutamine = "GLN"
    case glycine = "GLY"
    case histidine = "HIS"
    case isoleucine = "ILE"
    case leucine = "LEU"
    case lysine = "LYS"
    case methionine = "MET"
    case phenylalanine = "PHE"
    case proline = "PRO"
    case serine = "SER"
    case threonine = "THR"
    case tryptophan = "TRP"
    case tyrosine = "TYR"
    case valine = "VAL"
    case selenocysteine = "SEC"
    case pyrrolysine = "PYL"
    case asparagineOrAsparticAcid = "ASX"
    case glutamineOrGlutamicAcid = "GLX"
    case unknown = "UNK"
    
    init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let residue = Residue.allCases.first(where: { $0.rawValue == trimmed }) {
            self = residue
        } else {
            self = .unknown
        }
    }
} 