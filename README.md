# ZigString
A string class for the Zig programming language to manipulate UTF-8 strings.
Uses SIMD or linear operations. Under the hood it works with graphemes only. See src/tests.zig for details.
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

    var correct2 = ArrayList([]const u8).init(alloc);
    defer correct2.deinit();
    try correct2.append("Hello,");
    try correct2.append("World!");

    for (hello_split.items, correct2.items) |l, r| {
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
