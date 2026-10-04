import Foundation
import Testing
import LivepaperImport
import LivepaperWorkshop

/// What an item's page on Steam Community says about it. The pages here are
/// written for the test in the shape of Steam's markup, with made-up items.
struct WorkshopItemPageTests {
    static func page(
        title: String = "Paper Lanterns",
        app: String = "431960",
        type: String? = "Scene",
        preview: String? = "https://images.steamusercontent.com/ugc/1/ABC/?imw=637&amp;imh=358"
    ) -> String {
        let typeTag = type.map {
            """
            <div data-panel="{&quot;type&quot;:&quot;PanelGroup&quot;}" class="workshopTags">\
            <span class="workshopTagsTitle">Type:&nbsp;</span>\
            <a href="https://steamcommunity.com/workshop/browse/?appid=\(app)&requiredtags%5B%5D=\($0)">\($0)</a></div>
            """
        } ?? ""
        let previewImage = preview.map { #"<img id="previewImage" class="workshopItemPreviewImageEnlargeable" src="\#($0)"/>"# } ?? ""
        return """
        <html><head><title>Steam Workshop::\(title)</title></head><body>
        <div class="breadcrumbs">
        <a data-panel="{&quot;noFocusRing&quot;:true}" href="https://steamcommunity.com/app/\(app)">Some App</a>\
        <span class="breadcrumb_separator">&nbsp;&gt;&nbsp;</span>
        </div>
        \(previewImage)
        <div class="rightDetailsBlock">\(typeTag)<div class="workshopTags"><span class="workshopTagsTitle">Genre:&nbsp;</span>\
        <a href="https://steamcommunity.com/workshop/browse/?appid=\(app)&requiredtags%5B%5D=Nature">Nature</a></div></div>
        </body></html>
        """
    }

    @Test func `reads a scene's page`() {
        let page = WorkshopItemPage(html: Self.page())
        #expect(page.app == 431_960)
        #expect(page.title == "Paper Lanterns")
        #expect(page.type == "Scene")
        #expect(page.preview?.absoluteString == "https://images.steamusercontent.com/ugc/1/ABC/?imw=637&imh=358")
        #expect(page.refusal == nil)
    }

    @Test func `a title's entities are read as the characters they stand for`() {
        let page = WorkshopItemPage(html: Self.page(title: "Rain &amp; Neon &quot;Nights&quot; &#39;24 &lt;3"))
        #expect(page.title == "Rain & Neon \"Nights\" '24 <3")
    }

    static let refusals: [Row<(app: String, type: String?), WorkshopRefusal?>] = [
        Row("a scene", ("431960", "Scene"), nil),
        Row("a video", ("431960", "Video"), nil),
        Row("a page that names no type", ("431960", nil), nil),
        Row("a web page, which runs code of its own", ("431960", "Web"), .skipped(.wallpaperEngine(.runsCode("web")))),
        Row("an application, the same", ("431960", "Application"), .skipped(.wallpaperEngine(.runsCode("application")))),
        Row("another game's item", ("4000", "Scene"), .notWallpaperEngine),
    ]

    @Test(arguments: refusals)
    func `refuses before downloading what the import would refuse after`(row: Row<(app: String, type: String?), WorkshopRefusal?>) {
        #expect(WorkshopItemPage(html: Self.page(app: row.input.app, type: row.input.type)).refusal == row.expected)
    }

    @Test func `a page that is not an item's says nothing, and refuses nothing`() {
        let page = WorkshopItemPage(html: "<html><head><title>Steam Community :: Wallpaper Engine</title></head><body></body></html>")
        #expect(page == WorkshopItemPage(app: nil, title: nil, type: nil, preview: nil))
        #expect(page.refusal == nil)
    }

    @Test func `a preview that is not on https is not loaded`() {
        #expect(WorkshopItemPage(html: Self.page(preview: "http://images.steamusercontent.com/ugc/1/ABC/")).preview == nil)
        #expect(WorkshopItemPage(html: Self.page(preview: "file:///etc/hosts")).preview == nil)
        #expect(WorkshopItemPage(html: Self.page(preview: nil)).preview == nil)
    }

    @Test func `the refusal's words are the import's own`() {
        let page = WorkshopItemPage(html: Self.page(type: "Web"))
        #expect(page.refusal?.words == skipWords(.wallpaperEngine(.runsCode("web"))))
        #expect(WorkshopRefusal.notWallpaperEngine.words == workshopFailureWords(.notWallpaperEngine).reason)
    }
}
