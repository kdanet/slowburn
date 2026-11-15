import BudgetCore
import QuotaKit
import SwiftUI

/// What a blob is busy with. While its agent works it sits at the laptop doing what the agent's log says;
/// while the agent rests it picks one of forty pastimes.
///
/// Each activity is a pose (`Motion.pose…`, how the body and eyes move) plus props (`ActivityProps.draw…`),
/// grouped by theme in the `Art…` files.
enum Activity: String, CaseIterable, Sendable {
    // Work: always at the laptop, one per `WorkKind`.
    case typing, coding, searching, terminal, testing, building, shipping,
         browsing, delegating, thinking, planning, debugging, asking
    // Pastimes: quiet ones.
    case reading, coffee, music, juggling, bubbles, meditating, gardening, yoyo, balloon, stargazing
    // Outdoors and on the move.
    case fishing, kite, paperPlane, jumpRope, hulaHoop, skateboard, snowfall, butterfly, dandelion, swimRing
    // Hobbies.
    case painting, knitting, guitar, drums, gaming, disco, camera, rubik, cardHouse, fishbowl
    // Treats, sport and lazing about.
    case iceCream, watermelon, popcorn, campfire, sunbathing, rain, hammock, dumbbells, basketball, football

    /// The laptop activity for what the agent is doing; both lists share raw values.
    init(work: WorkKind) { self = Activity(rawValue: work.rawValue) ?? .typing }

    var isWork: Bool { WorkKind(rawValue: rawValue) != nil }

    static let work: [Activity] = allCases.filter(\.isWork)
    static let leisure: [Activity] = allCases.filter { !$0.isWork }
    /// How long one pastime lasts before the blob picks another.
    static let leisureSlot: TimeInterval = 3 * 60

    var name: String {
        switch self {
        case .typing: "пишет ответ"
        case .coding: "правит код"
        case .searching: "ищет в коде"
        case .terminal: "в терминале"
        case .testing: "гоняет тесты"
        case .building: "собирает"
        case .shipping: "выкатывает"
        case .browsing: "ищет в сети"
        case .delegating: "раздаёт задачи"
        case .thinking: "думает"
        case .planning: "планирует"
        case .debugging: "чинит ошибку"
        case .asking: "ждёт ответа"
        case .reading: "читает"
        case .coffee: "пьёт кофе"
        case .music: "слушает музыку"
        case .juggling: "жонглирует"
        case .bubbles: "пускает пузыри"
        case .meditating: "медитирует"
        case .gardening: "поливает росток"
        case .yoyo: "играет с йо-йо"
        case .balloon: "гуляет с шариком"
        case .stargazing: "смотрит на звёзды"
        case .fishing: "рыбачит"
        case .kite: "запускает змея"
        case .paperPlane: "пускает самолётик"
        case .jumpRope: "прыгает через скакалку"
        case .hulaHoop: "крутит обруч"
        case .skateboard: "катается на скейте"
        case .snowfall: "ловит снежинки"
        case .butterfly: "гоняется за бабочкой"
        case .dandelion: "дует на одуванчик"
        case .swimRing: "плавает с кругом"
        case .painting: "рисует"
        case .knitting: "вяжет"
        case .guitar: "играет на гитаре"
        case .drums: "стучит на барабанах"
        case .gaming: "играет в приставку"
        case .disco: "танцует"
        case .camera: "фотографирует"
        case .rubik: "крутит кубик"
        case .cardHouse: "строит домик из карт"
        case .fishbowl: "смотрит на рыбок"
        case .iceCream: "ест мороженое"
        case .watermelon: "ест арбуз"
        case .popcorn: "ест попкорн"
        case .campfire: "жарит маршмеллоу"
        case .sunbathing: "загорает"
        case .rain: "гуляет под дождём"
        case .hammock: "дремлет в гамаке"
        case .dumbbells: "качается"
        case .basketball: "ведёт мяч"
        case .football: "чеканит мяч"
        }
    }

    /// The pastime for this moment. The two blobs walk the list with a stride coprime to its length,
    /// half a list apart, so they never do the same thing. A sleeping blob (budget gone) just sleeps.
    static func leisure(provider: Provider, mood: Mood, now: Date) -> Activity? {
        if mood == .sleepy { return nil }
        let n = leisure.count
        let slot = Int((now.timeIntervalSinceReferenceDate / leisureSlot).rounded(.down))
        let offset = provider == .claude ? 0 : n / 2
        let i = ((slot * 7 + offset) % n + n) % n
        return leisure[i]
    }
}

// MARK: - Shared helpers for poses and props

let tau = 2 * Double.pi

/// 0..<1 through a repeating period.
func phase(_ t: Double, _ period: Double) -> Double {
    let p = t.truncatingRemainder(dividingBy: period) / period
    return p < 0 ? p + 1 : p
}

/// Smoothstep, clamped: soft start and stop.
func smooth(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }

/// 0 → 1 → 0 over `p` in 0...1, eased.
func bump(_ p: Double) -> Double { sin(.pi * min(max(p, 0), 1)) }

// MARK: - Dispatch

extension Motion {
    /// The mood's body language, calmed down to suit the activity, then bent by the activity itself.
    static func at(_ mood: Mood, activity: Activity?, t: Double) -> Motion {
        guard let activity else { return at(mood, t: t) }
        // Bouncing or shivering would fight a book or a mug; worry and blindness still show.
        let base: Mood = mood == .worried || mood == .unknown ? mood : .calm
        var m = at(base, t: t)
        m.pose(activity, t)
        return m
    }

    mutating func pose(_ activity: Activity, _ t: Double) {
        switch activity {
        case .typing: poseTyping(t)
        case .coding: poseCoding(t)
        case .searching: poseSearching(t)
        case .terminal: poseTerminal(t)
        case .testing: poseTesting(t)
        case .building: poseBuilding(t)
        case .shipping: poseShipping(t)
        case .browsing: poseBrowsing(t)
        case .delegating: poseDelegating(t)
        case .thinking: poseThinking(t)
        case .planning: posePlanning(t)
        case .debugging: poseDebugging(t)
        case .asking: poseAsking(t)
        case .reading: poseReading(t)
        case .coffee: poseCoffee(t)
        case .music: poseMusic(t)
        case .juggling: poseJuggling(t)
        case .bubbles: poseBubbles(t)
        case .meditating: poseMeditating(t)
        case .gardening: poseGardening(t)
        case .yoyo: poseYoyo(t)
        case .balloon: poseBalloon(t)
        case .stargazing: poseStargazing(t)
        case .fishing: poseFishing(t)
        case .kite: poseKite(t)
        case .paperPlane: posePaperPlane(t)
        case .jumpRope: poseJumpRope(t)
        case .hulaHoop: poseHulaHoop(t)
        case .skateboard: poseSkateboard(t)
        case .snowfall: poseSnowfall(t)
        case .butterfly: poseButterfly(t)
        case .dandelion: poseDandelion(t)
        case .swimRing: poseSwimRing(t)
        case .painting: posePainting(t)
        case .knitting: poseKnitting(t)
        case .guitar: poseGuitar(t)
        case .drums: poseDrums(t)
        case .gaming: poseGaming(t)
        case .disco: poseDisco(t)
        case .camera: poseCamera(t)
        case .rubik: poseRubik(t)
        case .cardHouse: poseCardHouse(t)
        case .fishbowl: poseFishbowl(t)
        case .iceCream: poseIceCream(t)
        case .watermelon: poseWatermelon(t)
        case .popcorn: posePopcorn(t)
        case .campfire: poseCampfire(t)
        case .sunbathing: poseSunbathing(t)
        case .rain: poseRain(t)
        case .hammock: poseHammock(t)
        case .dumbbells: poseDumbbells(t)
        case .basketball: poseBasketball(t)
        case .football: poseFootball(t)
        }
    }
}

extension ActivityProps {
    func draw(_ ctx: inout GraphicsContext) {
        switch activity {
        case .typing: drawTyping(&ctx)
        case .coding: drawCoding(&ctx)
        case .searching: drawSearching(&ctx)
        case .terminal: drawTerminal(&ctx)
        case .testing: drawTesting(&ctx)
        case .building: drawBuilding(&ctx)
        case .shipping: drawShipping(&ctx)
        case .browsing: drawBrowsing(&ctx)
        case .delegating: drawDelegating(&ctx)
        case .thinking: drawThinking(&ctx)
        case .planning: drawPlanning(&ctx)
        case .debugging: drawDebugging(&ctx)
        case .asking: drawAsking(&ctx)
        case .reading: drawReading(&ctx)
        case .coffee: drawCoffee(&ctx)
        case .music: drawMusic(&ctx)
        case .juggling: drawJuggling(&ctx)
        case .bubbles: drawBubbles(&ctx)
        case .meditating: drawMeditating(&ctx)
        case .gardening: drawGardening(&ctx)
        case .yoyo: drawYoyo(&ctx)
        case .balloon: drawBalloon(&ctx)
        case .stargazing: drawStargazing(&ctx)
        case .fishing: drawFishing(&ctx)
        case .kite: drawKite(&ctx)
        case .paperPlane: drawPaperPlane(&ctx)
        case .jumpRope: drawJumpRope(&ctx)
        case .hulaHoop: drawHulaHoop(&ctx)
        case .skateboard: drawSkateboard(&ctx)
        case .snowfall: drawSnowfall(&ctx)
        case .butterfly: drawButterfly(&ctx)
        case .dandelion: drawDandelion(&ctx)
        case .swimRing: drawSwimRing(&ctx)
        case .painting: drawPainting(&ctx)
        case .knitting: drawKnitting(&ctx)
        case .guitar: drawGuitar(&ctx)
        case .drums: drawDrums(&ctx)
        case .gaming: drawGaming(&ctx)
        case .disco: drawDisco(&ctx)
        case .camera: drawCamera(&ctx)
        case .rubik: drawRubik(&ctx)
        case .cardHouse: drawCardHouse(&ctx)
        case .fishbowl: drawFishbowl(&ctx)
        case .iceCream: drawIceCream(&ctx)
        case .watermelon: drawWatermelon(&ctx)
        case .popcorn: drawPopcorn(&ctx)
        case .campfire: drawCampfire(&ctx)
        case .sunbathing: drawSunbathing(&ctx)
        case .rain: drawRain(&ctx)
        case .hammock: drawHammock(&ctx)
        case .dumbbells: drawDumbbells(&ctx)
        case .basketball: drawBasketball(&ctx)
        case .football: drawFootball(&ctx)
        }
    }
}
