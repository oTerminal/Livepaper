import Foundation
import Testing
import LivepaperWorkshop

/// Links to Workshop items, as a page in the Workshop window, a paste or a drop gives them.
struct WorkshopLinkTests {
    static let lonelyCat: UInt64 = 3_289_988_463

    static let links: [Row<String, UInt64?>] = [
        Row("an item's page", "https://steamcommunity.com/sharedfiles/filedetails/?id=3289988463", lonelyCat),
        Row(
            "an item's page with the Workshop's search left on it",
            "https://steamcommunity.com/sharedfiles/filedetails/?id=3289988463&searchtext=cat",
            lonelyCat
        ),
        Row("the path without its last slash", "https://steamcommunity.com/sharedfiles/filedetails?id=3289988463", lonelyCat),
        Row("the Workshop's older path", "https://steamcommunity.com/workshop/filedetails/?id=3289988463", lonelyCat),
        Row("plain http, which Steam moves to https", "http://steamcommunity.com/sharedfiles/filedetails/?id=3289988463", lonelyCat),
        Row("with www", "https://www.steamcommunity.com/sharedfiles/filedetails/?id=3289988463", lonelyCat),
        Row("the host in capitals", "https://SteamCommunity.com/sharedfiles/filedetails/?id=3289988463", lonelyCat),
        Row("Steam's own link to an item", "steam://url/CommunityFilePage/3289988463", lonelyCat),
        Row("the smallest id", "https://steamcommunity.com/sharedfiles/filedetails/?id=1", 1),

        Row(
            "another site whose name starts with Steam's",
            "https://steamcommunity.com.example.org/sharedfiles/filedetails/?id=3289988463",
            nil
        ),
        Row("a lookalike host", "https://steamcommunlty.com/sharedfiles/filedetails/?id=3289988463", nil),
        Row("a name and password in the link", "https://someone:secret@steamcommunity.com/sharedfiles/filedetails/?id=3289988463", nil),
        Row("a port of its own", "https://steamcommunity.com:8443/sharedfiles/filedetails/?id=3289988463", nil),
        Row("the Workshop's front page", "https://steamcommunity.com/app/431960/workshop/", nil),
        Row("an item's change notes", "https://steamcommunity.com/sharedfiles/filedetails/changelog/3289988463", nil),
        Row("no id", "https://steamcommunity.com/sharedfiles/filedetails/?searchtext=cat", nil),
        Row("an id that is not a number", "https://steamcommunity.com/sharedfiles/filedetails/?id=cat", nil),
        Row("a signed id", "https://steamcommunity.com/sharedfiles/filedetails/?id=+3289988463", nil),
        Row("an id of zero", "https://steamcommunity.com/sharedfiles/filedetails/?id=0", nil),
        Row("an id too large for Steam", "https://steamcommunity.com/sharedfiles/filedetails/?id=18446744073709551616", nil),
        Row("two ids", "https://steamcommunity.com/sharedfiles/filedetails/?id=1&id=2", nil),
        Row("a file", "file:///Users/someone/3289988463", nil),
        Row("Steam's link to something else", "steam://url/StoreAppPage/431960", nil),
    ]

    @Test(arguments: links)
    func `reads the item a link is to`(row: Row<String, UInt64?>) throws {
        let url = try #require(URL(string: row.input))
        #expect(WorkshopLink.item(in: url)?.value == row.expected)
    }

    static let pasted: [Row<String, UInt64?>] = [
        Row("a link", "https://steamcommunity.com/sharedfiles/filedetails/?id=3289988463", lonelyCat),
        Row("a link with space around it", "  https://steamcommunity.com/sharedfiles/filedetails/?id=3289988463\n", lonelyCat),
        Row("the item's number alone", "3289988463", lonelyCat),
        Row("the number with space around it", " 3289988463 ", lonelyCat),
        Row("words around the number", "item 3289988463", nil),
        Row("two lines", "3289988463\n3289988464", nil),
        Row("nothing", "", nil),
        Row("a link to somewhere else", "https://example.org/?id=3289988463", nil),
    ]

    @Test(arguments: pasted)
    func `reads the item pasted text names`(row: Row<String, UInt64?>) {
        #expect(WorkshopLink.item(inPasted: row.input)?.value == row.expected)
    }

    @Test func `an item's page is where its link leads`() throws {
        let item = try #require(WorkshopItemID(Self.lonelyCat))
        #expect(WorkshopLink.page(of: item).absoluteString == "https://steamcommunity.com/sharedfiles/filedetails/?id=3289988463")
        #expect(WorkshopLink.item(in: WorkshopLink.page(of: item)) == item)
    }

    @Test func `the Workshop opens on Wallpaper Engine's front page`() {
        #expect(WorkshopLink.front.absoluteString == "https://steamcommunity.com/app/431960/workshop/")
    }

    static let navigations: [Row<String, WorkshopLink.Navigation>] = [
        Row("the Workshop's front page", "https://steamcommunity.com/app/431960/workshop/", .inWindow),
        Row("an item's page", "https://steamcommunity.com/sharedfiles/filedetails/?id=3289988463", .inWindow),
        Row("a search of the Workshop", "https://steamcommunity.com/workshop/browse/?appid=431960&requiredtags%5B%5D=Scene", .inWindow),
        Row("Steam Community's sign-in page", "https://steamcommunity.com/login/home/", .inWindow),
        Row("plain http to Steam Community", "http://steamcommunity.com/app/431960/workshop/", .inBrowser),
        Row("the Steam store", "https://store.steampowered.com/app/431960/", .inBrowser),
        Row("a link out of an item's description", "https://example.org/", .inBrowser),
        Row("Steam's own link to an item", "steam://url/CommunityFilePage/3289988463", .refused),
        Row("a script", "javascript:alert(1)", .refused),
        Row("a file", "file:///etc/hosts", .refused),
        Row("a page made of data", "data:text/html,hello", .refused),
    ]

    @Test(arguments: navigations)
    func `keeps the window on Steam Community and sends the rest to the browser`(row: Row<String, WorkshopLink.Navigation>) throws {
        let url = try #require(URL(string: row.input))
        #expect(WorkshopLink.navigation(to: url) == row.expected)
    }

    @Test func `an id is a positive number`() {
        #expect(WorkshopItemID(0) == nil)
        #expect(WorkshopItemID(1)?.description == "1")
        #expect(WorkshopItemID("3289988463")?.value == Self.lonelyCat)
        #expect(WorkshopItemID("032") == nil)
        #expect(WorkshopItemID("") == nil)
    }
}
