import QtQuick
import qs.singletons

// The notification body markup: what is kept, dropped, escaped and linked
TestCase {
    suiteName: "NotificationMarkup"

    readonly property var _colors: ({ link: "#0000ff", unusualLink: "#ff8800", imageRow: "#222222", imageGlyph: "#999999", address: "#777777" })

    function _rich(body) {
        return NotificationMarkup.richText(body, _colors);
    }

    function run() {
        // --- link kinds ---
        assertEqual(NotificationMarkup.linkKind("https://example.com"), "standard", "linkKind: https is standard");
        assertEqual(NotificationMarkup.linkKind("HTTP://example.com"), "standard", "linkKind: scheme case ignored");
        assertEqual(NotificationMarkup.linkKind("mailto:a@b.c"), "standard", "linkKind: mailto is standard");
        assertEqual(NotificationMarkup.linkKind("file:///etc/passwd"), "unusual", "linkKind: file is unusual");
        assertEqual(NotificationMarkup.linkKind("steam://run/1"), "unusual", "linkKind: an app's scheme is unusual");
        assertEqual(NotificationMarkup.linkKind("/home/user/a.png"), "unusual", "linkKind: an absolute path is unusual");
        assertEqual(NotificationMarkup.linkKind("data:image/png;base64,AAAA"), "", "linkKind: data URI is no link");
        assertEqual(NotificationMarkup.linkKind("javascript:alert(1)"), "", "linkKind: javascript is no link");
        assertEqual(NotificationMarkup.linkKind("relative/path"), "", "linkKind: no scheme, not absolute: no link");
        assertEqual(NotificationMarkup.linkTarget("/a/b.png"), "file:///a/b.png", "linkTarget: a path is a file URL");

        // --- formatting ---
        assertEqual(_rich("<b>bold</b> <i>it</i> <u>u</u>"), "<b>bold</b> <i>it</i> <u>u</u>", "rich: b, i, u kept");
        assertEqual(_rich("<B>x</B>"), "<b>x</b>", "rich: tag case ignored");
        assertEqual(_rich("<b>open"), "<b>open</b>", "rich: an unclosed tag is closed");
        assertEqual(_rich("<b><i>x</b>y</i>"), "<b><i>x</i></b><i>y</i>", "rich: crossed tags: inner closed and reopened");
        assertEqual(_rich("</b>x"), "x", "rich: a stray closing tag dropped");
        assertEqual(_rich("<span style=\"x\">t</span><script>s</script>"), "ts", "rich: other tags dropped, text kept");
        assertEqual(_rich("a\nb<br/>c<p>d</p>"), "a<br>b<br>c<br>d<br>", "rich: new lines, br and p are line breaks");
        assertEqual(_rich("<p>first</p>"), "first<br>", "rich: no break before a leading paragraph");

        // --- escaping ---
        assertEqual(_rich("a < b & c > d"), "a &lt; b &amp; c &gt; d", "rich: stray < & > escaped");
        assertEqual(_rich("&amp; &lt; &#65; &#x42;"), "&amp; &lt; A B", "rich: entities decoded, escaped again where needed");
        assertEqual(_rich("&bogus;"), "&amp;bogus;", "rich: an unknown entity escaped");
        assertEqual(_rich("say \"hi\""), "say &quot;hi&quot;", "rich: quotes escaped");

        // --- the tokenizer: tags of any shape ---
        assertEqual(_rich("a<br>b<br/>c<br />d<BR/>e"), "a<br>b<br>c<br>d<br>e", "tokens: br in every spelling");
        assertEqual(_rich("<b/>x"), "x", "tokens: a self-closing b opens nothing");
        assertEqual(_rich("<a href=\"https://x/?q=a>b\">t</a>"),
            "<a href=\"https://x/?q=a&gt;b\"><span style=\"color:#0000ff\">t</span></a>",
            "tokens: a > inside a quoted attribute does not end the tag");
        assertEqual(_rich("<a href=https://bare>t</a>"), "<a href=\"https://bare\"><span style=\"color:#0000ff\">t</span></a>",
            "tokens: a bare attribute value");
        assertEqual(_rich("a<!-- hidden <b> -->b<!DOCTYPE html><?xml x?>c"), "abc", "tokens: comments and declarations dropped");
        assertEqual(_rich("<o:p>x</o:p><my-tag a=1>y</my-tag>"), "xy", "tokens: odd tag names are tags, dropped");
        assertEqual(_rich("I <3 you, 1<2"), "I &lt;3 you, 1&lt;2", "tokens: a < that starts no tag is text");
        assertEqual(_rich("<b class=\"x\" >sp</b >"), "<b>sp</b>", "tokens: spaces and attributes inside tags");
        assertEqual(_rich("<a href=\"https://x\" unclosed"), "&lt;a href=&quot;https://x&quot; unclosed",
            "tokens: a tag never closed is text");
        {
            const parsed = NotificationMarkup.tokens("<IMG SRC='a.png' Alt=\"x &amp; y\" />");
            assertEqual(JSON.stringify(parsed), JSON.stringify([{ type: "open", name: "img",
                attributes: { src: "a.png", alt: "x & y" }, selfClosing: true }]),
                "tokens: names lower case, values decoded, self-closing marked");
        }

        // --- links ---
        assertEqual(_rich("<a href=\"https://x.org/?a=1&amp;b=2\">site</a>"),
            "<a href=\"https://x.org/?a=1&amp;b=2\"><span style=\"color:#0000ff\">site</span></a>",
            "rich: a standard link in the link colour, its address re-escaped");
        assertEqual(_rich("<a href='steam://run/1'>game</a>"),
            "<a href=\"steam://run/1\"><span style=\"color:#ff8800\">game</span></a>",
            "rich: an unusual link in the warning colour");
        assertEqual(_rich("<a href=\"javascript:x()\">no</a>"), "no", "rich: a link without a usable target is text");
        assertEqual(_rich("<a href=\"https://a\" onclick=\"x\">a</a>"),
            "<a href=\"https://a\"><span style=\"color:#0000ff\">a</span></a>", "rich: other attributes dropped");
        assertEqual(_rich("<a href=\"https://a\">open"), "<a href=\"https://a\"><span style=\"color:#0000ff\">open</span></a>",
            "rich: an unclosed link is closed");
        assertEqual(_rich("<a href=\"https://a\"><a href=\"https://b\">x</a>"),
            "<a href=\"https://a\"><span style=\"color:#0000ff\">x</span></a>", "rich: no link inside a link");

        // --- images ---
        {
            const image = _rich("see <img src=\"https://cdn.example/p.png\" alt=\"Photo\"> here");
            assert(image.indexOf("<table width=\"100%\"") > 0 && image.indexOf("bgcolor=\"#222222\"") > 0,
                "rich: an image is a tinted row of its own");
            assert(image.indexOf("<a href=\"https://cdn.example/p.png\"><span style=\"color:#0000ff\">Photo</span></a>") > 0,
                "rich: an image row links to the image, labelled by its alt text");
            assert(image.indexOf("<span style=\"color:#777777\">https://cdn.example/p.png</span>") > 0,
                "rich: an image row with alt text shows its address too");
            assert(image.indexOf("<img") === -1, "rich: no image is loaded");
            const noAlt = _rich("<img src=\"/tmp/a.png\">");
            assert(noAlt.indexOf(">/tmp/a.png</span></a>") > 0 && noAlt.indexOf("color:#ff8800") > 0,
                "rich: an image without alt text labelled by its address; a file is an unusual link");
            const data = _rich("<img src=\"data:image/png;base64,AAAA\" alt=\"Inline\">");
            assert(data.indexOf("<a ") === -1 && data.indexOf("Inline") > 0, "rich: a data image is its alt text, no link");
            assertEqual(_rich("<img src=\"data:x\">"), "", "rich: an image with nothing to show is dropped");
        }

        // --- image links ---
        assertEqual(JSON.stringify(NotificationMarkup.imageLinks(
            "<img src=\"https://a/p.png\"/><a href=\"https://b\">b</a><img src=\"/tmp/x.png\"><img src=\"data:x\">")),
            JSON.stringify(["https://a/p.png", "file:///tmp/x.png"]), "imageLinks: the image rows' targets, not other links or data");

        // --- plain text ---
        assertEqual(NotificationMarkup.plainText("<b>Code</b> &amp; <a href=\"https://x/123456\">link</a>"),
            "Code & link", "plain: tags dropped, entities decoded, addresses gone");
        assertEqual(NotificationMarkup.plainText("a<br>b<img src=\"x\" alt=\"pic\">c"), "a\nb\npic\nc",
            "plain: line breaks, images as their alt text");
        assertEqual(NotificationMarkup.plainText("a < b"), "a < b", "plain: a stray < kept");
    }
}
