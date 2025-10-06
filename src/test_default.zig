const std = @import("std");
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const alloc = std.testing.allocator;
const mtl = @import("mtl.zig");

const String = @import("String.zig").String;
const CaseSensitive = String.CaseSensitive;
const Codepoint = String.Codepoint;
const Context = String.Context;
const Index = String.Index;
const KeepEmptyParts = String.KeepEmptyParts;
// Don't change this string, many tests depend on it:
const JoseStr = "Jos\u{65}\u{301} se fu\u{65}\u{301} a Sevilla sin pararse";
const theme = String.Theme.Dark;

test "Append Test" {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const additional = "[Ещё]";
    const correct_cstr = JoseStr ++ additional;

    var main_str = try String.From(JoseStr);
    defer main_str.deinit();
    try main_str.addUtf8(additional);
    
    var bytes_buf = try main_str.toUtf8();
    defer bytes_buf.deinit();
    try expectEqualStrings(bytes_buf.items, correct_cstr);
}

test "Get Grapheme Index" {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const main_str = try String.From(JoseStr);
    defer main_str.deinit();
    // std.debug.print("String cp count: {}, gr count={}\n", .{main_str.codepoints.items.len,
    //     main_str.grapheme_count});
    {
        const index = main_str.findIndex(4) orelse return String.Error.NotFound;
        //std.debug.print("Grapheme at {} is at codepoint {}\n", .{index.gr, index.cp});
        try expect(index.cp == 5);
    }   
    {
        const index = main_str.findIndex(13) orelse return String.Error.NotFound;
        //std.debug.print("Grapheme at {} is at codepoint {}\n", .{index.gr, index.cp});
        try expect(index.cp == 15);
    }
    {
        const index = main_str.findIndex(0) orelse return String.Error.NotFound;
        //std.debug.print("Grapheme at {} is at codepoint {}\n", .{index.gr, index.cp});
        try expect(index.cp == 0);
    }
    {
        const index = main_str.findIndex(32) orelse return String.Error.NotFound;
        //std.debug.print("Grapheme at {} is at codepoint {}\n", .{index.gr, index.cp});
        try expect(index.cp == 34);
    }
}

test "Trim Left" {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const trim_left_str = "  \t Привет!";
    var main_str = try String.From(trim_left_str);
    defer main_str.deinit();
    { // trim tabs and empty spaces
        main_str.trimLeft();
        const buf = try main_str.toUtf8();
        defer buf.deinit();
        // std.debug.print("{s}(): \"{s}\" => \"{s}\"\n", .{@src().fn_name, trim_left_str, buf.items});
        try expectEqualStrings(buf.items, "Привет!");
    }

    const orig_str = "Hi!";
    { // trim nothing from left
        var s = try String.From(orig_str);
        defer s.deinit();
        s.trimLeft();
        const buf = try s.toUtf8();
        defer buf.deinit();
        // std.debug.print("{s}(): \"{s}\" => \"{s}\"\n", .{@src().fn_name, orig_str, buf.items});
        try expectEqualStrings(orig_str, buf.items);
    }
}

test "Trim Right" {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const trim_right_str = "Привет! \t  ";
    var main_str = try String.From(trim_right_str);
    defer main_str.deinit();
    {
        main_str.trimRight();
        const buf = try main_str.toUtf8();
        defer buf.deinit();
        // std.debug.print("{s}(): \"{s}\" => \"{s}\"\n", .{@src().fn_name, trim_right_str, buf.items});
        try expectEqualStrings(buf.items, "Привет!");
    }
 
    const orig_str = "Hi!";
    {
        var s = try String.From(orig_str);
        defer s.deinit();
        s.trimRight();
        const buf = try s.toUtf8();
        defer buf.deinit();
        // std.debug.print("{s}(): \"{s}\" => \"{s}\"\n", .{@src().fn_name, orig_str, buf.items});
        try expectEqualStrings(orig_str, buf.items);
    }
}

test "Substring" {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const main_str = try String.From("Jos\u{65}\u{301} se fu\u{65}\u{301}");
    defer main_str.deinit();
    {
        const sub = try main_str.substring(4, 6);
        defer sub.deinit();
        const buf = try sub.toUtf8();
        defer buf.deinit();
        //std.debug.print("{s}:{} \"{s}\"\n", .{@src().fn_name, @src().line, buf.items});
        try expectEqualStrings(buf.items, " se fu");
    }

    {
        const sub = try main_str.substring(1, 3);
        defer sub.deinit();
        const buf = try sub.toUtf8();
        defer buf.deinit();
        //std.debug.print("{s}:{} \"{s}\"\n", .{@src().fn_name, @src().line, buf.items});
        try expectEqualStrings(buf.items, "osé");
    }
    {
        const sub = try main_str.substring(8, -1); //-1=till the end of string
        defer sub.deinit();
        const buf = try sub.toUtf8();
        defer buf.deinit();
        //std.debug.print("{s}:{} \"{s}\"\n", .{@src().fn_name, @src().line, buf.items});
        try expectEqualStrings(buf.items, "fué");
    }
}

test "Equals" {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const c_str = "my file.desktop";
    const filename = try String.From(c_str);
    defer filename.deinit();
    const ext = ".desKtop";
    {
        const result = filename.endsWithUtf8(ext, .{});
        try expect(!result);
        //std.debug.print("\"{s}\" ends with {s}(cs.Yes): {}\n", .{ c_str, ext, result });
    }
    {
        const result = filename.endsWithUtf8(ext, .{.cs = .No});
        try expect(result);
        //std.debug.print("\"{s}\" ends with {s}(cs.No): {}\n", .{ c_str, ext, result });
    }

    const str1 = try String.From(".desktop");
    defer str1.deinit();
    const str2 = try String.From(".desKtop");
    defer str2.deinit();
    try expect(!str1.equals(str2, .{}));
    try expect(str1.equals(str2, .{.cs = .No}));
}

test "FindInsertRemove" {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();
    
    const html_ascii = "<human><name>Jos\u{65}\u{301}</name><age>27</age></human>\u{65}\u{301}";
    const html_str = try String.From(html_ascii);
    defer html_str.deinit();

    {
        const idx = html_str.lastIndexOfAscii("Jos", .{.cs = .Yes}) orelse return error.NotFound;
        // try html_str.printGraphemes(@src());
        // try html_str.printCodepoints(@src());
        // mtl.debug(@src(), "idx:{}", .{idx});
        try expect(idx.cp == 13 and idx.gr == 13);

        const idx2 = html_str.lastIndexOfAscii("<hu", .{}) orelse return error.NotFound;
        try expect(idx2.cp == 0 and idx2.gr == 0);
    }

    {
        const from = html_str.indexOfAscii("/human", .{}) orelse return error.NotFound;
        const idx = html_str.lastIndexOfAscii("human", .{.from = from}) orelse return error.NotFound;
        // mtl.debug(@src(), "from={}, found at={}", .{from, idx});
        try expect(idx.cp == 1 and idx.gr == 1);
    }

    {
        const from = html_str.lastIndexOfAscii("h", .{}) orelse return error.NotFound;
        const idx = html_str.lastIndexOfAscii("a", .{.from=from}) orelse return error.NotFound;
        // mtl.debug(@src(), "idx: {}, from: {}", .{idx, from});
        try expect(idx.cp == 34 and idx.gr == 33);
    }

    {
        const str_to_find = try String.toCodepoints(alloc, "</age>");
        defer str_to_find.deinit();
        const index = html_str.indexOfCpSlice(str_to_find.items, .{.cs=.No})
            orelse return error.NotFound;
        try expect(index.cp == 32 and index.gr == 31);
    }
    
    const initial_str = "Jos\u{65}\u{301} no se va";
    {
        var s = try String.From(initial_str);
        defer s.deinit();
        try s.remove("os\u{65}\u{301}");
        const buf = try s.toUtf8();
        defer buf.deinit();
        try expectEqualStrings(buf.items, "J no se va");
    }
    {
        var s = try String.From(initial_str);
        defer s.deinit(); 
        try s.insertUtf8(s.findIndex(5), "举报");
        const buf = try s.toUtf8();
        defer buf.deinit();
        try expectEqualStrings("José 举报no se va", buf.items);
    }
    {
        var s = try String.From(initial_str);
        defer s.deinit();
        const start_from = s.indexOfAscii("no", .{.cs = .No});
        try s.replaceUtf8(start_from, 2, "si\u{301}");
        const buf = try s.toUtf8();
        defer buf.deinit();
        try expectEqualStrings("José sí se va", buf.items);
    }
    {
        var s = try String.From(initial_str);
        defer s.deinit();
        var jo_str = try String.FromAscii("JO");
        defer jo_str.deinit();
        try expect(!s.startsWith(jo_str, .{}));
        try expect(s.startsWith(jo_str, .{.cs = .No}));

        var foo = try String.FromAscii("Foo");
        defer foo.deinit();
        try expect(!s.startsWith(foo, .{}));
        
        const str_end = "se va";
        try expect(s.endsWithUtf8(str_end, .{}));
        try expect(!s.endsWith(foo, .{}));
    }


}

test "Split" {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const main_str = try String.From(JoseStr);
    defer main_str.deinit();
    // the next 2 functions help the developer to visually dissect a string:
    // try main_str.printGraphemes(@src());
    // try main_str.printCodepoints(@src());

    // split(..) returns !ArrayList(String)
    const words = try main_str.split(" ", .{.keep = .No});
    defer {
        for (words.items) |item| {
            item.deinit();
        }
        words.deinit();
    }

    const correct = [_][]const u8 {"Jos\u{65}\u{301}", "se",
    "fu\u{65}\u{301}", "a", "Sevilla", "sin", "pararse"};
    try expect(words.items.len == correct.len);
    for (words.items, correct) |word, bytes| {
        try expect(word.equalsUtf8(bytes, .{}));
    }

    //============= another test
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

    //============= another test
    const empty_str = try String.FromAscii("Foo  Bar");
    defer empty_str.deinit();
    const empty_arr = try empty_str.split(" ", .{});
    defer {
        for (empty_arr.items) |item| {
            item.deinit();
        }
        empty_arr.deinit();
    }

    const correct3 = [_][]const u8 {"Foo", "", "Bar"};
    try expect(empty_arr.items.len == correct3.len);
    for (empty_arr.items, correct3) |str_obj, correct_word| {
        try expect(str_obj.equalsUtf8(correct_word, .{}));
    }

}

test "To Upper, To Lower" {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const normal = [_][]const u8 {"Hello, World!", "Привет!", "Jos\u{65}\u{301}"};
    const upper = [_][]const u8 {"HELLO, WORLD!", "ПРИВЕТ!", "JOS\u{45}\u{301}"};
    const lower = [_][]const u8 {"hello, world!", "привет!", "jos\u{65}\u{301}"};

    for (normal, upper, lower) |n, u, l| {
        var str = try String.From(n);
        defer str.deinit();
        try str.toUpper();
        try expect(str.equalsUtf8(u, .{}));
        try str.toLower();
        try expect(str.equalsUtf8(l, .{}));
    }
}

test "Char At" {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const str = try String.From(JoseStr);
    defer str.deinit();
    // try str.printCodepoints(@src());

    const needles = try String.FromAscii("se");
    defer needles.deinit();
    if (str.indexOf(needles, .{})) |idx| {
        try expect(idx.eq(.{.cp=6, .gr=5}));
    }

    const from = Index{.cp=2, .gr=2};
    if (str.indexOf(needles, .{.from=from})) |idx| {
        try expect(idx.eq(Index{.cp=6, .gr=5}));
    } else {
        return error.NotFound;
    }

    // toCpAscii() is slightly faster than toCp()
    const letter_s: Codepoint = 's';
    
    // String.charAt() returns a ?String.Grapheme object which
    // internally points to a section of the string object,
    // so it's invalid once the string changes.
    // But thanks to this it can hold an arbitrary long grapheme cluster
    // and doesn't need a deinit() call.
    try expect(str.charAt(2).?.eqCp(letter_s));
    try expect(str.charAt(32).?.eqCp('e'));

    const at: usize = 1;
    {
        const gr = str.charAt(at) orelse return error.NotFound;
        try expect(!gr.eqCp('a'));
        try expect(gr.eqCp('o'));
        try expect(!gr.eqCp('G'));
        try expect(!gr.eqUtf8("\u{65}\u{301}"));
    }

    {
        const gr = str.charAt(3) orelse return error.NotFound;
        try expect(gr.eqUtf8("\u{65}\u{301}"));
        try expect(!gr.eqCp('G'));
    }

    const str_ru = try String.From("Жизнь");
    defer str_ru.deinit();
    try expect(str_ru.startsWithUtf8("Ж", .{}));
    try expect(str_ru.charAt(4).?.eqUtf8("ь"));

    // So here's usage of charAtIndex() which is used to *efficiently*
    // iterate over a string forth and then backwards.
    // The usage of "\u{65}\u{301}" (2 codepoints)
    // instead of "é" (1 codepoint) is intentional to test that it
    // iterates over graphemes, not codepoints:
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

    {
        const jose = try String.From("Jos\u{65}\u{301}");
        defer jose.deinit();
        {
            if (jose.indexOfAscii("s", .{})) |idx| { // iterate from letter "s"
                var it = jose.iteratorFrom(idx);
                const correct = [_] Index {.{.cp=2, .gr=2}, .{.cp=3, .gr=3}};
                var i: usize = 0;
                while (it.next()) |gr| {
                    try expect(gr.idx.eq(correct[i]));
                    i += 1;
                }
            }
        }

        { // from zero
            var it = jose.iterator();
            const correct = [_] Index {.{.cp=0, .gr=0}, .{.cp=1, .gr=1},
                .{.cp=2, .gr=2}, .{.cp=3, .gr=3}};
            var i: usize = 0;
            while (it.next()) |gr| {
                try expect(gr.idx.eq(correct[i]));
                i += 1;
            }
        }

        { // backwards from a certain point
            const idx = String.Index {.cp = 3, .gr = 3};
            var it = jose.iteratorFrom(idx);
            const correct = [_] Index {.{.cp=3, .gr=3}, .{.cp=2, .gr=2}, .{.cp=1, .gr=1}, .{.cp=0, .gr=0}};
            var i: usize = 0;
            while (it.prev()) |gr| {
                // mtl.debug(@src(), "{} vs {}", .{gr.idx, correct[i]});
                try expect(gr.idx.eq(correct[i]));
                i += 1;
            }
        }

        { // backwards from string end
            var iter = jose.iteratorFromEnd();
            const correct = [_] Index { .{.cp=3, .gr=3}, .{.cp=2, .gr=2},
                .{.cp=1, .gr=1}, .{.cp=0, .gr=0}};
            var i: usize = 0;
            while (iter.prev()) |gr| {
                try expect(gr.idx.eq(correct[i]));
                i += 1;
            }
        }
    }
}

test "Slice functions" {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const heap = try String.From(JoseStr);
    defer heap.deinit();
    {
        const needle_utf8 = "\u{65}\u{301}";
        const idx = heap.indexOfUtf8(needle_utf8, .{}) orelse return error.NotFound;
        const slice = heap.midSlice(idx);
        const needle_str = try String.From(needle_utf8);
        defer needle_str.deinit();
        const needle_idx = slice.indexOf(needle_str, .{}) orelse return error.NotFound;
        // try heap.printGraphemes(@src());
        // try slice.printGraphemes(@src());
        // mtl.debug(@src(), "result: {}", .{needle_idx});
        try expect(needle_idx.eqCpGr(3, 3));
    }

    { // slice indexOf other slice
        const slice_start = heap.indexOfAscii("se", .{}) orelse return error.NotFound;
        const slice = heap.midSlice(slice_start);

        const needle_start = slice.indexOfUtf8("\u{65}\u{301} ", .{}) orelse return error.NotFound;
        const needle_end = slice.indexOfAscii("a", .{}) orelse return error.NotFound;
        const needle_slice = heap.slice(needle_start, needle_end); // needle_slice="é "
        const idx = slice.indexOfSlice(needle_slice, .{}) orelse return error.NotFound;
        // mtl.debug(@src(), "slice:{dt}, needle_slice:{dt}, indexOfSlice:{}, slice_start:{}", .{slice, needle_slice, idx, slice_start});
        try expect(idx.eqCpGr(11, 10));
    }

    { // matches
        const start = heap.indexOfAscii("se", .{}) orelse return error.NotFound;
        const slice = heap.midSlice(start);
        
        const g5 = slice.charAt(5) orelse return error.NotFound;
        try expect(g5.eqUtf8("\u{65}\u{301}"));

        const g7 = slice.charAt(7) orelse return error.NotFound;
        try expect(g7.eqUtf8("a"));

        try expect (slice.matchesAscii("a", .{.from=g7.idx}) != null);
        const g = slice.next(g7.idx) orelse return error.NotFound;
        try expect(g.eqCp(' '));
    }

    { // lastIndexOf
        const start = heap.indexOfAscii("se", .{}) orelse return error.NotFound;
        const slice = heap.midSlice(start);
        const idx = slice.lastIndexOfUtf8("\u{65}\u{301}", .{}) orelse return error.NotFound;
        try expect(idx.eqCpGr(11, 10));

        const idx_a = slice.lastIndexOfAscii("a", .{}) orelse return error.NotFound;
        try expect(idx_a.eqCpGr(31, 29));
    }

    { // find index
        const start = heap.indexOfAscii("se", .{}) orelse return error.NotFound;
        const slice = heap.midSlice(start);
        const idx = slice.findIndex(7) orelse return error.NotFound;
        const gr = slice.charAtIndex(idx) orelse return error.NotFound;
        try expect(gr.idx.eqCpGr(14, 12) and gr.eqCp('a'));
    }
}

// test "Qt chars" {
//     String.ctx = try Context.New(alloc);
//     defer String.ctx.deinit();
//     {
//         const s = try String.From("Jos\u{65}\u{301}");
//         defer s.deinit();
//         mtl.debug(@src(), "Count: {} {}", .{s.size(), s});
//     }
//     {
//         const s = try String.From("abc\u{00010139}def\u{00010102}g");
//         defer s.deinit();
//         mtl.debug(@src(), "Count: {} {}", .{s.size(), s});
//     }
// }