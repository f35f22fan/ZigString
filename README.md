# ZigString
A string class for the Zig programming language to correctly manipulate UTF-8 strings
by respecting grapheme cluster boundaries. As opposed to other String classes including
in other programming languages that operate on raw bytes or codepoints which is inherently flawed.
<p/>
When the user searches for a substring e.g. <code>my_str.indexOf("something")</code> he gets an <code>Index</code> struct in
 return which has two fields: <code>.gr</code> for grapheme index and
<code>.cp</code> for codepoint index (the user only needs the <code>.gr</code> field). This way when the next search
 is done from this position onward the implementation doesn't have to do a linear search up to
  that point while still respects grapheme boundaries. In short, this little user inconvenience 
  exists to achieve fast and correct searches and string manipulations.
<p/>
A visible letter/character is a grapheme (or "grapheme cluster" to sound fancier) that might
 be composed of more than one codepoints (but often it's one codepoint).
 <p/>
In this implementation under the hood each codepoint takes 21 bits (plus 1 separate bit to
 mark grapheme boundaries) because 21 bits is enough to store every UTF-8 codepoint.
Internally it uses SIMD or linear operations when needed. Under the hood it works with
 graphemes only unless explicitly otherwise specified in the API/docs. See the tests
 (from the /src folder) for examples.<br/>
Tested on Zig 0.14dev
<p/>
### Regex support is a work in progress
<p/>
Example:<br/>
 
 ```zig
    // before using the string class, must create a string context per thread, it contains cached amd shared data:
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const hello_world = try String.From("Hello, World!");
    defer hello_world.deinit();
    const hello_split = try hello_world.split(" ", CaseSensitive.Yes, KeepEmptyParts.No);
    defer {
        for(hello_split.items) |s| {
            s.deinit();
        }
        hello_split.deinit();
    }

    const correct2 = [_][]const u8 {"Hello,", "World!"};
    for (hello_split.items, correct2) |l, r| {
        try expect(l.equals(r, CaseSensitive.Yes));
    }

    const start_from: usize = 0;
    const at = hello_world.indexOf("lo", .{.from=start_from});
    if (at) |index| {
        try expect(index.gr == 3); // .gr=grapheme, .cp=codepoint
    } else {
        std.debug.print("IndexOf \"lo\" not found", .{});
    }

    const sub = try hello_world.substring(3, 5);
    defer sub.deinit();
    try expect(sub.equals("lo, W", CaseSensitive.Yes));

    const sub2 = try hello_world.substring(3, -1);
    defer sub2.deinit();
    try expect(sub2.equals("lo, World!", CaseSensitive.Yes));
    
    // Efficient iteration over graphemes:
    const both_ways = try String.From("Jos\u{65}\u{301}"); // "José"
    defer both_ways.deinit();
    {
        var it = both_ways.iterator();
        while (it.next()) |gr| { // ends up printing "José"
            std.debug.print("{}", .{gr}); // the grapheme's index is at gr.idx
        }
        std.debug.print("\n", .{});
    }
    
    {
        var it = both_ways.iteratorFrom(both_ways.strEnd());
        while (it.prev()) |gr| { // ends up printing "ésoJ"
            std.debug.print("{}", .{gr});
        }
        std.debug.print("\n", .{});
    }

    {
        // let's iterate from let's say the location of "s":
        if (both_ways.indexOf("s", .{})) |idx| {
            var it = both_ways.iteratorFrom(idx);
            while (it.next()) |gr| { // prints "sé"
                std.debug.print("{}", .{gr});
            }
            std.debug.print("\n", .{});
        }
    }

    // Some Chinese:
    const str_ch = try String.From("好久不见，你好吗？");
    defer str_ch.deinit();
    try expect(str_ch.charAt(0).?.eq("好"));
    try expect(str_ch.charAt(3).?.eq("见"));
    try expect(str_ch.charAt(8).?.eq("？"));
    try expect(!str_ch.charAt(1).?.eq("A"));

```
