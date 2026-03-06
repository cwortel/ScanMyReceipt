import Foundation

/// Suggests a receipt category based on shop name and OCR text using
/// simple keyword matching. No ML or network calls needed.
struct CategoryService {

    /// Keywords mapped to category names. Checked against the lowercased
    /// shop name and (optionally) the full OCR text.
    /// Order matters: first match wins.
    static let keywordMap: [(category: String, keywords: [String])] = [
        // Car Expenses
        ("Car Expenses", [
            "shell", "bp ", "total energies", "totalenergies", "tango", "tinq",
            "esso", "texaco", "gulf", "avia", "tamoil", "q8",
            "parking", "parkeer", "p+r", "anwb", "kwik-fit", "kwikfit",
            "halfords", "autozone", "garage", "carwash", "wasstraat",
        ]),
        // Travel
        ("Travel", [
            " ns ", "ns.nl", "nederlandse spoorwegen", "schiphol", "airport",
            "booking.com", "booking ", "airbnb", "hotel", "hostel",
            "uber", "taxi", "flixbus", "transavia", "klm", "ryanair",
            "easyjet", "9292", "ov-chipkaart", "ovpay",
        ]),
        // Telecom
        ("Telecom", [
            "kpn", "vodafone", "t-mobile", "tmobile", "ziggo", "tele2",
            "simyo", "ben ", "lebara", "odido",
        ]),
        // Equipment
        ("Equipment", [
            "coolblue", "bol.com", "mediamarkt", "media markt",
            "alternate", "azerty", "megekko", "apple store", "samsung",
            "ikea",
        ]),
        // Insurance
        ("Insurance", [
            "centraal beheer", "interpolis", "nationale-nederlanden",
            "nn ", "aegon", "allianz", "asr", "univé", "unive",
            "verzekering", "insurance",
        ]),
        // Subscriptions
        ("Subscriptions", [
            "spotify", "netflix", "disney", "adobe", "microsoft",
            "apple.com", "google storage", "dropbox", "github",
            "abonnement", "subscription",
        ]),
        // Office
        ("Office", [
            "bruna", "staples", "office centre", "bureau", "kantoor",
            "post nl", "postnl", "dhl", "ups",
        ]),
        // Representation
        ("Representation", [
            "bloemen", "flowers", "cadeau", "gift", "kaart",
        ]),
        // Food & Drinks — broad, keep near the end so more specific
        // categories match first.
        ("Food & Drinks", [
            "albert heijn", "jumbo", "lidl", "aldi", "plus ",
            "dirk", "coop", "spar ", "vomar", "picnic",
            "restaurant", "café", "cafe", "bistro", "eetcafé",
            "mcdonalds", "mcdonald", "burger king", "kfc",
            "domino", "subway", "starbucks", "coffee",
            "thuisbezorgd", "uber eats", "deliveroo",
            "bakker", "bakkerij", "slager",
        ]),
    ]

    /// Returns a suggested category for the given shop name and optional
    /// full OCR text. Returns an empty string when no match is found.
    static func suggestCategory(shopName: String, ocrText: String = "") -> String {
        // Build a single haystack from shop name + OCR text
        let haystack = " \(shopName) \(ocrText) ".lowercased()

        for (category, keywords) in keywordMap {
            for keyword in keywords {
                if haystack.contains(keyword) {
                    return category
                }
            }
        }
        return ""
    }
}
