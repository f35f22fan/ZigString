# Ctring
Ctring.zig - a Zig string class with O(1) access to graphemes.
Tested with Zig 0.15.2

See the bottom of Ctring.zig for more tests/usage examples.

(String.zig and Regex.zig are deprecated)

---

 ```zig
    // before using the string class, must create a string context per thread,
    // it contains cached amd shared data:
    const alloc = std.testing.allocator;
    try Ctring.Init(alloc);
    defer Ctring.Deinit();

    {
        var top = try Ctring.New("🧑‍🌾 橋 5b");
        defer top.deinit();

        {
            var v = top.view(0, 3);
            try expect(v.eqUtf8("🧑‍🌾 橋"));
            v.setView(4, 6);
            try expect(v.eqAscii("5b"));

            v.setView(0, 6);
            try expect(v.startsWith(top));
            try expect(v.startsWithUtf8("🧑‍🌾 橋"));
        }

        { // iterate over graphemes forward
            const correct = [_][]const u8 {"🧑‍🌾", " ", "橋", " ", "5", "b"};
            var iter = top.iterator(0);
            var idx: usize = 0;
            while (iter.next()) |gr| {
                try expect(gr.eqUtf8(correct[idx]));
                idx += 1;
            }
        }

        { // iterate over graphemes backwards
            const correct = [_][]const u8 {"b", "5", " ", "橋", " ", "🧑‍🌾"};
            var iter = top.iterator(top.last());
            var idx: usize = 0;
            while (iter.prev()) |gr| {
                try expect(gr.eqUtf8(correct[idx]));
                idx += 1;
            }
        }
    }

    {
        var top = try Ctring.New("🧑‍🌾 .橋 .5b.橋");
        defer top.deinit();
        const v = top.view(0, top.size());
        try expect(v.findAscii(".", null) == 2);
        try expect(v.findAscii(".", 3) == 5);
        try expect(v.findUtf8("橋", null) == 3);
        try expect(v.findUtf8(".橋", null) == 2);
        try expect(v.findUtf8("橋", 4) == 9);
        try expect(v.findUtf8(".橋", 3) == 8);
    }

    { // splitting
        var root = try Ctring.New("Hello,  world! Again!");
        defer root.deinit();
        const rootv = root.view(0, root.size());
        {
            var arr = try rootv.splitAscii(" ", true);
            defer arr.deinit(ctx.a);

            const correct = [_][]const u8{"Hello,", "", "world!", "Again!"};
            for (arr.items, correct) |a, b| {
                // mtl.debug(@src(), "{f} vs \"{s}\"", .{a._(2), b});
                try expect(a.eqAscii(b));
            }
        }
    }

```
