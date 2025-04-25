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
    var main_str = try String.From(JoseStr);
    defer main_str.deinit();
    const correct_cstr = JoseStr ++ additional;
    try main_str.add(additional);
    var test_buf = try main_str.toBytes();
    defer test_buf.deinit();
    try expectEqualStrings(test_buf.items, correct_cstr);
}

test "Get Grapheme Address" {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const main_str = try String.From(JoseStr);
    defer main_str.deinit();
    // std.debug.print("String cp count: {}, gr count={}\n", .{main_str.codepoints.items.len,
    //     main_str.grapheme_count});
    {
        const index = main_str.graphemeAddress(4) orelse return String.Error.NotFound;
        //std.debug.print("Grapheme at {} is at codepoint {}\n", .{index.gr, index.cp});
        try expect(index.cp == 5);
    }   
    {
        const index = main_str.graphemeAddress(13) orelse return String.Error.NotFound;
        //std.debug.print("Grapheme at {} is at codepoint {}\n", .{index.gr, index.cp});
        try expect(index.cp == 15);
    }
    {
        const index = main_str.graphemeAddress(0) orelse return String.Error.NotFound;
        //std.debug.print("Grapheme at {} is at codepoint {}\n", .{index.gr, index.cp});
        try expect(index.cp == 0);
    }
    {
        const index = main_str.graphemeAddress(32) orelse return String.Error.NotFound;
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
        try main_str.trimLeft();
        const buf = try main_str.toBytes();
        defer buf.deinit();
        // std.debug.print("{s}(): \"{s}\" => \"{s}\"\n", .{@src().fn_name, trim_left_str, buf.items});
        try expectEqualStrings(buf.items, "Привет!");
    }

    const orig_str = "Hi!";
    { // trim nothing from left
        var s = try String.From(orig_str);
        defer s.deinit();
        try s.trimLeft();
        const buf = try s.toBytes();
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
        try main_str.trimRight();
        const buf = try main_str.toBytes();
        defer buf.deinit();
        // std.debug.print("{s}(): \"{s}\" => \"{s}\"\n", .{@src().fn_name, trim_right_str, buf.items});
        try expectEqualStrings(buf.items, "Привет!");
    }
 
    const orig_str = "Hi!";
    {
        var s = try String.From(orig_str);
        defer s.deinit();
        try s.trimRight();
        const buf = try s.toBytes();
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
        const buf = try sub.toBytes();
        defer buf.deinit();
        //std.debug.print("{s}:{} \"{s}\"\n", .{@src().fn_name, @src().line, buf.items});
        try expectEqualStrings(buf.items, " se fu");
    }

    {
        const sub = try main_str.substring(1, 3);
        defer sub.deinit();
        const buf = try sub.toBytes();
        defer buf.deinit();
        //std.debug.print("{s}:{} \"{s}\"\n", .{@src().fn_name, @src().line, buf.items});
        try expectEqualStrings(buf.items, "osé");
    }
    {
        const sub = try main_str.substring(8, -1); //-1=till the end of string
        defer sub.deinit();
        const buf = try sub.toBytes();
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
        const result = filename.endsWithBytes(ext, .{});
        try expect(!result);
        //std.debug.print("\"{s}\" ends with {s}(cs.Yes): {}\n", .{ c_str, ext, result });
    }
    {
        const result = filename.endsWithBytes(ext, .{.cs = .No});
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

    // const chinese = try String.From(alloc, "违法和不良信息举报电话");
    // defer chinese.deinit();
    // try chinese.printGraphemes(std.debug);
    
    const str = "<human><name>Jos\u{65}\u{301}</name><age>27</age></human>\u{65}\u{301}";
    const haystack = try String.From(str);
    defer haystack.deinit();
    const cs = String.CaseSensitive.No  ;
    {
        const index = haystack.indexOfBytes("<human>", .{.cs = cs}) orelse return String.Error.NotFound;
        try expect(index.cp == 0 and index.gr == 0);
        const index2 = haystack.indexOfBytes("</human>", .{.cs = cs}) orelse return String.Error.NotFound;
        try expect(index2.cp == 38 and index2.gr == 37);
    }

    {
        const str_to_find = try String.toCodepoints(alloc, "</age>");
        defer str_to_find.deinit();
        const index = haystack.indexOfCpSlice(str_to_find.items, .{.cs=cs})
            orelse return String.Error.NotFound;
        try expect(index.cp == 32 and index.gr == 31);
    }
    
    const initial_str = "Jos\u{65}\u{301} no se va";
    {
        var s = try String.From(initial_str);
        defer s.deinit();
        try s.remove("os\u{65}\u{301}");
        const buf = try s.toBytes();
        defer buf.deinit();
        try expectEqualStrings(buf.items, "J no se va");
    }
    {
        var s = try String.From(initial_str);
        defer s.deinit();
        const needles = "no";
        const from = s.indexOfBytes(needles, .{.cs = cs});
        try s.removeByIndex(from, 200);
        const buf = try s.toBytes();
        defer buf.deinit();
        try expectEqualStrings(buf.items, "Jos\u{65}\u{301} ");
    }
    {
        var s = try String.From(initial_str);
        defer s.deinit(); 
        try s.insertBytes(s.At(5), "举报");
        const buf = try s.toBytes();
        defer buf.deinit();
        try expectEqualStrings("José 举报no se va", buf.items);
    }
    {
        var s = try String.From(initial_str);
        defer s.deinit();
        const start_from = s.indexOfBytes("no", .{.cs = cs});
        try s.replaceBytes(start_from, 2, "si\u{301}");
        const buf = try s.toBytes();
        defer buf.deinit();
        try expectEqualStrings("José sí se va", buf.items);
    }
    {
        var s = try String.From(initial_str);
        defer s.deinit();
        var jo_str = try String.From("JO");
        defer jo_str.deinit();
        try expect(!s.startsWith(jo_str, .{}));
        try expect(s.startsWith(jo_str, .{.cs = .No}));

        var foo = try String.From("Foo");
        defer foo.deinit();
        try expect(!s.startsWith(foo, .{}));
        
        const str_end = "se va";
        try expect(s.endsWithBytes(str_end, .{}));
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
    const words = try main_str.split(" ", CaseSensitive.Yes, KeepEmptyParts.No);
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
        try expect(word.equalsBytes(bytes, .{}));
    }

    //============= another test
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
        try expect(l.equalsBytes(r, .{}));
    }

    const start_from: usize = 0;
    const at = hello_world.indexOfBytes("lo", .{.from = start_from});
    if (at) |index| {
        try expect(index.gr == 3); // .gr=grapheme, .cp=codepoint
    } else {
        std.debug.print("IndexOf \"lo\" not found", .{});
    }

    const sub = try hello_world.substring(3, 5);
    defer sub.deinit();
    try expect(sub.equalsBytes("lo, W", .{}));

    const sub2 = try hello_world.substring(3, -1);
    defer sub2.deinit();
    try expect(sub2.equalsBytes("lo, World!", .{}));

    //============= another test
    const empty_str = try String.From("Foo  Bar");
    defer empty_str.deinit();
    const empty_arr = try empty_str.split(" ", CaseSensitive.Yes, KeepEmptyParts.Yes);
    defer {
        for (empty_arr.items) |item| {
            item.deinit();
        }
        empty_arr.deinit();
    }

    const correct3 = [_][]const u8 {"Foo", "", "Bar"};
    try expect(empty_arr.items.len == correct3.len);
    for (empty_arr.items, correct3) |str_obj, correct_word| {
        try expect(str_obj.equalsBytes(correct_word, .{}));
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
        try expect(str.equalsBytes(u, .{}));
        try str.toLower();
        try expect(str.equalsBytes(l, .{}));
    }
}

test "Char At" {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const str = try String.From(JoseStr);
    defer str.deinit();

    // toCpAscii() is slightly faster than toCp()
    const letter_s: Codepoint = try String.toCpAscii('s');
    
    // String.charAt() returns a ?String.Grapheme object which
    // internally points to a section of the string object,
    // so it's invalid once the string changes.
    // But thanks to this it can hold an arbitrary long grapheme cluster
    // and doesn't need a deinit() call.
    try expect(str.charAt(2).?.eqCp(letter_s));
    try expect(str.charAt(32).?.eqAscii('e'));

    const at: usize = 1;
    if (str.charAt(at)) |g| {
        try expect(!g.eqAscii('a'));
        try expect(g.eqAscii('o'));
        try expect(!g.eqAscii('G'));
        try expect(!g.eqBytes("\u{65}\u{301}"));
    } else {
        std.debug.print("Nothing found at {}\n", .{at});
    }

    if (str.charAt(3)) |g| {
        // const slice = g.getSlice() orelse return;
        // std.debug.print("{s}(): Grapheme len={}, slice=\"{any}\", index={}\n",
        //     .{@src().fn_name, g.len, slice, g.index()});
        try expect(g.eqBytes("\u{65}\u{301}"));
        try expect(!g.eqAscii('G'));
    }

    const str_ru = try String.From("Жизнь");
    defer str_ru.deinit();
    try expect(str_ru.charAt(0).?.eqCp(try String.toCp("Ж")));
    // When the method argument is known to be 1 codepoint one can use
    // the slightly faster method Grapheme.eqCp():
    try expect(str_ru.charAt(4).?.eqBytes("ь"));
    // Btw an even faster method is Grapheme.eqAscii() when the
    // method argument is known to be ASCII, like Grapheme.eqAscii('A').
    // Therefore, for example, it's wrong to use Grapheme.eqCp() with the following
    // method argument cause the grapheme has 2 codepoints \u65 and \u301:
    // try expect(!str_ru.charAt(4).?.eqCp("\u{65}\u{301}"));
    // The proper approach in this case is to use the slowest method - eqBytes():
    // try expect(!str_ru.charAt(4).?.eqBytes("\u{65}\u{301}"));

    
    // String.charAtIndex() is faster (almost O(1)) then CharAt(), which is O(n)
    // because each time CharAt() is called it iterates from the start
    // of the string to get to the grapheme at the given index,
    // while charAtIndex() goes straight to the given place inside the string.
    // So here's usage of charAtIndex() which is used to efficiently
    // iterate over a string to print it forth and then backwards:
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
        if (both_ways.indexOfBytes("s", .{})) |idx| {
            var it = both_ways.iteratorFrom(idx);
            while (it.next()) |gr| { // prints "sé"
                std.debug.print("{}", .{gr});
            }
            std.debug.print("\n", .{});
        }
    }

    const str_ch = try String.From("好久不见，你好吗？");
    defer str_ch.deinit();
    try expect(str_ch.charAt(0).?.eqBytes("好"));
    try expect(str_ch.charAt(3).?.eqBytes("见"));
    try expect(str_ch.charAt(8).?.eqBytes("？"));
    try expect(!str_ch.charAt(1).?.eqAscii('A'));

    if (true) {
        const s = try String.From("Jos\u{65}\u{301}");
        defer s.deinit();
        {
            if (s.indexOfBytes("s", .{})) |idx| { // iterate from letter "s"
                mtl.debug(@src(), "From {}: ", .{idx});
                var it = s.iteratorFrom(idx);
                while (it.next()) |gr| {
                    mtl.debug(@src(), "gr={}, gr.idx={}", .{gr, gr.idx});
                }
            }
        }

        {
            mtl.debug(@src(), "From zero: ", .{});
            var it = s.iterator();
            while (it.next()) |gr| {
                mtl.debug(@src(), "gr={}, gr.idx={}", .{gr, gr.idx});
            }
        }

        {
            const idx = String.Index {.cp = 2, .gr = 2};
            mtl.debug(@src(), "Backwards from: {}", .{idx});
            var it = s.iteratorFrom(idx);
            while (it.prev()) |gr| {
                mtl.debug(@src(), "gr={}, gr.idx={}", .{gr, gr.idx});
            }
        }

        {
            const idx = s.strEnd();
            mtl.debug(@src(), "Backwards from: {}", .{idx});
            var it = s.iteratorFrom(idx);
            while (it.prev()) |gr| {
                mtl.debug(@src(), "gr={}, gr.idx={}", .{gr, gr.idx});
            }
        }
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