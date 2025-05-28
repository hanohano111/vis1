import Foundation

public enum AtomElement: String, CaseIterable {
    case hydrogen = "H"
    case helium = "He"
    case lithium = "Li"
    case beryllium = "Be"
    case boron = "B"
    case carbon = "C"
    case nitrogen = "N"
    case oxygen = "O"
    case fluorine = "F"
    case neon = "Ne"
    case sodium = "Na"
    case magnesium = "Mg"
    case aluminum = "Al"
    case silicon = "Si"
    case phosphorus = "P"
    case sulfur = "S"
    case chlorine = "Cl"
    case argon = "Ar"
    case potassium = "K"
    case calcium = "Ca"
    case scandium = "Sc"
    case titanium = "Ti"
    case vanadium = "V"
    case chromium = "Cr"
    case manganese = "Mn"
    case iron = "Fe"
    case cobalt = "Co"
    case nickel = "Ni"
    case copper = "Cu"
    case zinc = "Zn"
    case gallium = "Ga"
    case germanium = "Ge"
    case arsenic = "As"
    case selenium = "Se"
    case bromine = "Br"
    case krypton = "Kr"
    case rubidium = "Rb"
    case strontium = "Sr"
    case yttrium = "Y"
    case zirconium = "Zr"
    case niobium = "Nb"
    case molybdenum = "Mo"
    case technetium = "Tc"
    case ruthenium = "Ru"
    case rhodium = "Rh"
    case palladium = "Pd"
    case silver = "Ag"
    case cadmium = "Cd"
    case indium = "In"
    case tin = "Sn"
    case antimony = "Sb"
    case tellurium = "Te"
    case iodine = "I"
    case xenon = "Xe"
    case cesium = "Cs"
    case barium = "Ba"
    case lanthanum = "La"
    case cerium = "Ce"
    case praseodymium = "Pr"
    case neodymium = "Nd"
    case promethium = "Pm"
    case samarium = "Sm"
    case europium = "Eu"
    case gadolinium = "Gd"
    case terbium = "Tb"
    case dysprosium = "Dy"
    case holmium = "Ho"
    case erbium = "Er"
    case thulium = "Tm"
    case ytterbium = "Yb"
    case lutetium = "Lu"
    case hafnium = "Hf"
    case tantalum = "Ta"
    case tungsten = "W"
    case rhenium = "Re"
    case osmium = "Os"
    case iridium = "Ir"
    case platinum = "Pt"
    case gold = "Au"
    case mercury = "Hg"
    case thallium = "Tl"
    case lead = "Pb"
    case bismuth = "Bi"
    case polonium = "Po"
    case astatine = "At"
    case radon = "Rn"
    case francium = "Fr"
    case radium = "Ra"
    case actinium = "Ac"
    case thorium = "Th"
    case protactinium = "Pa"
    case uranium = "U"
    case neptunium = "Np"
    case plutonium = "Pu"
    case americium = "Am"
    case curium = "Cm"
    case berkelium = "Bk"
    case californium = "Cf"
    case einsteinium = "Es"
    case fermium = "Fm"
    case mendelevium = "Md"
    case nobelium = "No"
    case lawrencium = "Lr"
    case rutherfordium = "Rf"
    case dubnium = "Db"
    case seaborgium = "Sg"
    case bohrium = "Bh"
    case hassium = "Hs"
    case meitnerium = "Mt"
    case darmstadtium = "Ds"
    case roentgenium = "Rg"
    case copernicium = "Cn"
    case nihonium = "Nh"
    case flerovium = "Fl"
    case moscovium = "Mc"
    case livermorium = "Lv"
    case tennessine = "Ts"
    case oganesson = "Og"
    
    init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let element = AtomElement.allCases.first(where: { $0.rawValue == trimmed }) {
            self = element
        } else {
            return nil
        }
    }
    
    // 新增: 标准Van der Waals半径 (单位：埃, Å)
    // 数据来源: Bondi, A. (1964). "Van der Waals Volumes and Radii". J. Phys. Chem. 68 (3): 441–451.
    // 以及 Mantina, M. et al. (2009). "Consistent van der Waals radii for the whole main group". J. Phys. Chem. A. 113 (19): 5806–5812.
    private static let vdwRadii: [AtomElement: Float] = [
        .hydrogen: 1.20,
        .helium: 1.40,
        .lithium: 1.82,
        .beryllium: 1.53,
        .boron: 1.92,
        .carbon: 1.70,
        .nitrogen: 1.55,
        .oxygen: 1.52,
        .fluorine: 1.47,
        .neon: 1.54,
        .sodium: 2.27,
        .magnesium: 1.73,
        .aluminum: 1.84,
        .silicon: 2.10,
        .phosphorus: 1.80,
        .sulfur: 1.80,
        .chlorine: 1.75,
        .argon: 1.88,
        .potassium: 2.75,
        .calcium: 2.31,
        .iron: 2.05,
        .cobalt: 1.88,
        .zinc: 1.39,
        .copper: 1.40,
        .bromine: 1.85,
        .iodine: 1.98
    ]
    
    // 默认半径，用于未定义具体半径的元素
    private static let defaultRadius: Float = 1.70
    
    /// 获取元素的Van der Waals半径 (Å)
    public var vanDerWaalsRadius: Float {
        return AtomElement.vdwRadii[self] ?? AtomElement.defaultRadius
    }
    
    /// 获取元素的Van der Waals半径 (内部单位，转换为纳米或适合RealityKit的单位)
    public var radiusForRendering: Float {
        // 将埃(Å)转换为纳米(nm)，1埃 = 0.1纳米
        // 再根据RealityKit空间比例调整
        return vanDerWaalsRadius * 0.01 // 转换为适合RealityKit的单位
    }
    
    /// 获取元素的颜色 (RGBA)
    public var color: (r: Float, g: Float, b: Float, a: Float) {
        switch self {
        case .hydrogen:
            return (1.0, 1.0, 1.0, 1.0) // 白色
        case .carbon:
            return (0.5, 0.5, 0.5, 1.0) // 灰色
        case .nitrogen:
            return (0.0, 0.0, 1.0, 1.0) // 蓝色
        case .oxygen:
            return (1.0, 0.0, 0.0, 1.0) // 红色
        case .phosphorus:
            return (1.0, 0.5, 0.0, 1.0) // 橙色
        case .sulfur:
            return (1.0, 1.0, 0.0, 1.0) // 黄色
        case .iron:
            return (0.7, 0.5, 0.2, 1.0) // 棕色
        case .cobalt:
            return (0.7, 0.0, 0.7, 1.0) // 紫色
        case .zinc:
            return (0.5, 0.5, 0.5, 1.0) // 灰色
        case .magnesium:
            return (0.0, 0.8, 0.0, 1.0) // 绿色
        case .calcium:
            return (0.5, 0.0, 0.5, 1.0) // 紫色
        case .chlorine:
            return (0.0, 0.8, 0.0, 1.0) // 绿色
        case .fluorine:
            return (0.0, 0.8, 0.8, 1.0) // 青绿色
        case .bromine:
            return (0.6, 0.2, 0.2, 1.0) // 深红棕
        case .iodine:
            return (0.4, 0.0, 0.8, 1.0) // 深紫
        case .sodium:
            return (0.0, 0.0, 1.0, 1.0) // 蓝色
        case .potassium:
            return (0.8, 0.0, 0.8, 1.0) // 紫色
        default:
            return (0.8, 0.8, 0.8, 1.0) // 默认浅灰色
        }
    }
} 
