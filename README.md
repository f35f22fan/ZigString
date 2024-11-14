# ZigString
A string class for the Zig programming language to manipulate UTF-8 strings.<p/>
A visible letter/character is a grapheme that might be composed of more than one codepoints (almost always it's one codepoint).<p/>
Each codepoint takes 21 bits (plus 1 bit to mark if it's also the start of a grapheme) because 21 bits is enough to store every UTF-8 codepoint.
Internally it uses SIMD or linear operations when needed. Under the hood it works with graphemes only unless otherwise specified. See src/tests.zig for details.<br/>
Tested on Zig 0.13
<br/><br/>
Example:<br/>
<pre>
    const hello_world = try String.From(alloc, "Hello, World!");
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
    const at = hello_world.indexOf("lo", start_from, CaseSensitive.Yes);
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
</pre>
