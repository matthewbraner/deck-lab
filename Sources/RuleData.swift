import Foundation
struct MasterDuelRules:Codable {
    let fetched:Date
    let limits:[String:Int]
}
extension MDM {
    static func rules() async throws -> MasterDuelRules {
        var limits:[String:Int]=[:],seen=Set<String>(),offset=0
        while true {
            let data=try await request("cards",items:[.init(name:"limit",value:"1000"),.init(name:"skip",value:String(offset)),.init(name:"sort",value:"_id"),.init(name:"fields",value:"name,banStatus,release")])
            let object=try JSONSerialization.jsonObject(with:data)
            let page=(object as? [[String:Any]]) ?? (object as? [String:Any]).map{[$0]} ?? []
            if page.isEmpty { break };var fresh=0
            for card in page {
                guard let id=card["_id"] as? String,let name=card["name"] as? String else { throw DataError.message("Invalid Master Duel card-rules response.") }
                if !seen.insert(id).inserted { continue };fresh+=1
                guard let released=card["release"] as? String,released<=ISO8601DateFormatter().string(from:Date()) else { continue }
                let limit:Int
                switch card["banStatus"] as? String {
                case "Forbidden":limit=0
                case "Limited 1":limit=1
                case "Limited 2":limit=2
                case nil,"Unlimited":limit=3
                default:throw DataError.message("Unknown Master Duel card-limit status. Rules were not replaced.")
                }
                limits[collectionKey(name)]=limit
            }
            guard fresh>0 else { throw DataError.message("Master Duel repeated a card-rules page.") };offset+=page.count
        }
        guard limits.count>10000 else { throw DataError.message("Master Duel returned incomplete card rules.") }
        return MasterDuelRules(fetched:Date(),limits:limits)
    }
}
// Official March 1, 2010 Advanced Format list, fixed for Edison.
// https://img.yugioh-card.com/en/downloads/alt_format/2010-03-01.pdf
let edisonLimits:[String:Int] = {
    let forbidden="""
BLACK LUSTER SOLDIER - ENVOY OF THE BEGINNING
CHAOS EMPEROR DRAGON - ENVOY OF THE END
CYBER JAR
CYBER-STEIN
DARK MAGICIAN OF CHAOS
DESTINY HERO - DISK COMMANDER
FIBER JAR
MAGICAL SCIENTIST
MAGICIAN OF FAITH
MAKYURA THE DESTRUCTOR
SINISTER SERPENT
TRIBE-INFECTING VIRUS
TSUKUYOMI
VICTORY DRAGON
WITCH OF THE BLACK FOREST
YATA-GARASU
THOUSAND-EYES RESTRICT
DARK STRIKE FIGHTER
BUTTERFLY DAGGER - ELMA
CARD OF SAFE RETURN
CHANGE OF HEART
CONFISCATION
DARK HOLE
DELINQUENT DUO
DIMENSION FUSION
GRACEFUL CHARITY
HARPIE'S FEATHER DUSTER
LAST WILL
METAMORPHOSIS
MIRAGE OF NIGHTMARE
MONSTER REBORN
PAINFUL CHOICE
POT OF GREED
PREMATURE BURIAL
RAIGEKI
SNATCH STEAL
TEMPLE OF THE KINGS
THE FORCEFUL SENTRY
CRUSH CARD VIRUS
EXCHANGE OF THE SPIRIT
IMPERIAL ORDER
LAST TURN
RING OF DESTRUCTION
SIXTH SENSE
TIME SEAL
"""
    let limited="""
LEFT ARM OF THE FORBIDDEN ONE
LEFT LEG OF THE FORBIDDEN ONE
RIGHT ARM OF THE FORBIDDEN ONE
RIGHT LEG OF THE FORBIDDEN ONE
BLACKWING - GALE THE WHIRLWIND
CARD TROOPER
CHAOS SORCERER
DARK ARMED DRAGON
ELEMENTAL HERO STRATOS
EXODIA THE FORBIDDEN ONE
GLADIATOR BEAST BESTIARI
GORZ THE EMISSARY OF DARKNESS
LUMINA, LIGHTSWORN SUMMONER
MARSHMALLON
MEZUKI
MIND MASTER
MORPHING JAR
NECRO GARDNA
NECROFACE
NEO-SPACIAN GRAND MOLE
NIGHT ASSAILANT
PLAGUESPREADER ZOMBIE
RESCUE CAT
SANGAN
SNIPE HUNTER
SPIRIT REAPER
SUMMONER MONK
TRAGOEDIA
BLACK ROSE DRAGON
BRIONAC, DRAGON OF THE ICE BARRIER
GOYO GUARDIAN
ADVANCED RITUAL ART
ALLURE OF DARKNESS
BRAIN CONTROL
BURIAL FROM A DIFFERENT DIMENSION
CARD DESTRUCTION
CHARGE OF THE LIGHT BRIGADE
COLD WAVE
DESTINY DRAW
EMERGENCY TELEPORT
FOOLISH BURIAL
FUTURE FUSION
GIANT TRUNADE
HEAVY STORM
LEVEL LIMIT - AREA B
LIMITER REMOVAL
MEGAMORPH
MIND CONTROL
MONSTER GATE
MYSTICAL SPACE TYPHOON
ONE FOR ONE
OVERLOAD FUSION
REASONING
REINFORCEMENT OF THE ARMY
SCAPEGOAT
SWORDS OF REVEALING LIGHT
CALL OF THE HAUNTED
CEASEFIRE
GRAVITY BIND
MAGIC CYLINDER
MAGICAL EXPLOSION
MIND CRUSH
MIRROR FORCE
OJAMA TRIO
RETURN FROM THE DIFFERENT DIMENSION
SOLEMN JUDGMENT
THE TRANSMIGRATION PROPHECY
TORRENTIAL TRIBUTE
TRAP DUSTSHOOT
WALL OF REVEALING LIGHT
"""
    let semi="""
CYBER DRAGON
DANDYLION
DESTINY HERO - MALICIOUS
GOBLIN ZOMBIE
HONEST
JUDGMENT DRAGON
LONEFIRE BLOSSOM
TREEBORN FROG
DEMISE, KING OF ARMAGEDDON
DEWLOREN, TIGER KING OF THE ICE BARRIER
BLACK WHIRLWIND
CHAIN STRIKE
GOLD SARCOPHAGUS
MAGICAL STONE EXCAVATION
UNITED WE STAND
BOTTOMLESS TRAP HOLE
ROYAL DECREE
ROYAL OPPRESSION
SKILL DRAIN
ULTIMATE OFFERING
"""
    var result:[String:Int]=[:]
    for (list,limit) in [(forbidden,0),(limited,1),(semi,2)] { for name in list.split(separator:"\n") { result[collectionKey(String(name))]=limit } }
    return result
}()
