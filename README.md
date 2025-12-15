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

Random ZigString examples:<br/>
 
 ```zig
    // before using the string class, must create a string context per thread, it contains cached amd shared data:
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const hello_world = try String.From("Hello, World!");
    defer hello_world.deinit();
    const hello_split = try hello_world.split(" ", .{.keep = .No});
    defer {
        for(hello_split.items) |s| {
            s.deinit();
        }
        hello_split.deinit();
    }

    const correct2 = [_][]const u8 {"Hello,", "World!"};
    for (hello_split.items, correct2) |l, r| {
        try expect(l.equalsUtf8(r, .{}));
    }

    const at = hello_world.indexOfAscii("lo", .{});
    if (at) |index| {
        // mtl.debug(@src(), "at={}", .{index});
        try expect(index.gr == 3);
    } else {
        std.debug.print("IndexOf \"lo\" not found", .{});
    }

    const sub = try hello_world.substring(3, 5);
    defer sub.deinit();
    try expect(sub.equalsUtf8("lo, W", .{}));

    const sub2 = try hello_world.substring(3, -1);
    defer sub2.deinit();
    try expect(sub2.equalsUtf8("lo, World!", .{}));
    
    // Efficient iteration over graphemes:
    const both_ways = try String.From("Jos\u{65}\u{301}"); // "José"
    defer both_ways.deinit();
    {
        var result = String.New();
        defer result.deinit();
        var it = both_ways.iterator();
        while (it.next()) |gr| {
            try result.addGrapheme(gr); // the grapheme's index is at gr.idx
        }
        
        try expect(both_ways.equals(result, .{}));
    }
    
    {
        const correct = "\u{65}\u{301}soJ"; // "ésoJ"
        var result = String.New();
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
        var result = String.New();
        defer result.deinit();
        if (both_ways.indexOfAscii("s", .{})) |idx| {
            var it = both_ways.iteratorFrom(idx);
            while (it.next()) |gr| {
                try result.addGrapheme(gr);
            }
            
            try expect(result.equalsUtf8(correct, .{}));
        }
    }

    const str_ch = try String.From("好久不见，你好吗？");
    defer str_ch.deinit();
    try expect(str_ch.charAt(0).?.eqUtf8("好"));
    try expect(str_ch.charAt(3).?.eqUtf8("见"));
    try expect(str_ch.charAt(8).?.eqUtf8("？"));
    try expect(!str_ch.charAt(1).?.eqCp('A'));

```
