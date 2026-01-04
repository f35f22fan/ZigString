# ZigString
A string class for the Zig programming language to correctly manipulate UTF-8 strings
by respecting grapheme cluster boundaries. As opposed to other String classes including
in other programming languages and tools such as Qt that operate on raw bytes or codepoints which is inherently flawed.
<p/>
The index of a char (grapheme cluster) inside a ZigString is represented by an Index struct which has 2 fields:
<code>.cp</code> is the index of the codepoint, and <code>.gr</code> is the index of the grapheme,
the latter is what the user actually needs.<br/>
<code>.cp</code> is used internally by the library
to avoid O(n) lookups when resuming a search from a given grapheme and instead do O(1).
<br/>
For example <code>my_str.indexOf("something", .{})</code> returns such an <code>Index</code>.

<p/>
General info: a visible letter/character is a grapheme (or "grapheme cluster") that might
 be composed of more than one codepoints (but often it's one codepoint).
<p/>
In this implementation under the hood each codepoint takes 21 bits (plus 1 separate bit to
 mark grapheme boundaries) because 21 bits are enough to store every UTF-8 codepoint.
Internally it uses SIMD or linear operations depending on the string length.

<p/>
For code examples check out the tests.
<br/>
Tested with Zig 0.15.2

---

### Regex support is mostly done, backtracking not planned

Example: finding an email address.
Since emails can contain Unicode in domain names using \w is a bad approach.
One can either set the <code>regex.charset = .Unicode</code> (default is .Ascii) which will
allow graphemes above ASCII to be part of <code>\w</code>,
or use instead the custom escape code <code>\u</code> which is the same as
<code>\w</code> except that it also includes one-codepoint unicode letters, including
Chinese. Thus for example if this email regex pattern:

> [\u.%+-]+@[\u-]+(\.\u{2,})+

Tries to find email addresses in the string:

> You can contact us at 用户_@例子.广告 or support@example.рф or sales@company.co.uk

It will find as expected 3 matches:

* 用户_@例子.广告
* support@example.рф
* sales@company.co.uk

---

Some String examples, see test_default.zig for more:<br/>
 
 ```zig
    // before using the string class, must create a string context per thread,
    // it contains cached amd shared data:
    try String.Init(alloc);
    defer String.Deinit();

    const str_ru = try String.New("Жизнь");
    defer str_ru.deinit();
    try expect(str_ru.startsWithUtf8("Ж", .{}));
    try expect(str_ru.charAt(4).?.eqUtf8("ь"));

    // So here's usage of charAtIndex() which is used to *efficiently*
    // iterate over a string forth and then backwards.
    // The usage of "\u{65}\u{301}" (2 codepoints)
    // instead of "é" (1 codepoint) is intentional to test that it
    // iterates over graphemes, not codepoints:
    const both_ways = try String.New("Jos\u{65}\u{301}"); // "José"
    defer both_ways.deinit();
    {
        var result = String.Empty();
        defer result.deinit();
        var it = both_ways.iterator();
        while (it.next()) |gr| {
            try result.addGrapheme(gr); // the grapheme's index is at gr.idx
        }

        try expect(both_ways.equals(result, .{}));
    }

    {
        const correct = "\u{65}\u{301}soJ"; // "ésoJ"
        var result = String.Empty();
        defer result.deinit();
        var it = both_ways.iteratorFromEnd();
        while (it.prev()) |gr| {
            try result.addGrapheme(gr);
        }

        try expect(result.equalsUtf8(correct, .{}));
    }

    {
        // let's iterate from let's say the location of "s":
        const correct = "s\u{65}\u{301}"; // "sé"
        var result = String.Empty();
        defer result.deinit();
        if (both_ways.indexOfAscii("s", .{})) |idx| {
            var it = both_ways.iteratorFrom(idx);
            while (it.next()) |gr| {
                try result.addGrapheme(gr);
            }

            try expect(result.equalsUtf8(correct, .{}));
        }
    }

    const str_ch = try String.New("好久不见，你好吗？");
    defer str_ch.deinit();
    try expect(str_ch.charAt(0).?.eqUtf8("好"));
    try expect(str_ch.charAt(3).?.eqUtf8("见"));
    try expect(str_ch.charAt(8).?.eqUtf8("？"));
    try expect(!str_ch.charAt(1).?.eqCp('A'));

```
