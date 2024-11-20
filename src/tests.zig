const std = @import("std");
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const alloc = std.testing.allocator;

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
    var ctx = try Context.New(alloc);
    defer ctx.deinit();
    const additional = "[Ещё]";
    var main_str = try String.From(alloc, ctx, JoseStr);
    defer main_str.deinit();
    const chained = JoseStr ++ additional;
    try main_str.append(ctx, additional);
    var utf8_buf = try main_str.toString();
    defer utf8_buf.deinit();
    try expectEqualStrings(utf8_buf.items, chained);
}

test "Get Grapheme Address" {
    var ctx = try Context.New(alloc);
    defer ctx.deinit();
    const main_str = try String.From(alloc, ctx, JoseStr);
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
    var ctx = try Context.New(alloc);
    defer ctx.deinit();
    const trim_left_str = "  \t Привет!";
    var main_str = try String.From(alloc, ctx, trim_left_str);
    defer main_str.deinit();
    {
        try main_str.trimLeft();
        const buf = try main_str.toString();
        defer buf.deinit();
        // std.debug.print("{s}(): \"{s}\" => \"{s}\"\n", .{@src().fn_name, trim_left_str, buf.items});
        try expectEqualStrings(buf.items, "Привет!");
    }

    const orig_str = "Hi!";
    {
        var trim_nothing_str = try String.From(alloc, ctx, orig_str);
        defer trim_nothing_str.deinit();
        try trim_nothing_str.trimLeft();
        const buf = try trim_nothing_str.toString();
        defer buf.deinit();
        // std.debug.print("{s}(): \"{s}\" => \"{s}\"\n", .{@src().fn_name, orig_str, buf.items});
        try expectEqualStrings(orig_str, buf.items);
    }
}

test "Trim Right" {
    var ctx = try Context.New(alloc);
    defer ctx.deinit();
    const trim_right_str = "Привет! \t  ";
    var main_str = try String.From(alloc, ctx, trim_right_str);
    defer main_str.deinit();
    {
        try main_str.trimRight();
        const buf = try main_str.toString();
        defer buf.deinit();
        // std.debug.print("{s}(): \"{s}\" => \"{s}\"\n", .{@src().fn_name, trim_right_str, buf.items});
        try expectEqualStrings(buf.items, "Привет!");
    }
 
    const orig_str = "Hi!";
    {
        var str = try String.From(alloc, ctx, orig_str);
        defer str.deinit();
        try str.trimRight();
        const buf = try str.toString();
        defer buf.deinit();
        // std.debug.print("{s}(): \"{s}\" => \"{s}\"\n", .{@src().fn_name, orig_str, buf.items});
        try expectEqualStrings(orig_str, buf.items);
    }
}

test "Substring" {
    var ctx = try Context.New(alloc);
    defer ctx.deinit();
    const main_str = try String.From(alloc, ctx, "Jos\u{65}\u{301} se fu\u{65}\u{301}");
    defer main_str.deinit();
     {
        const sub = try main_str.substring(4, 6);
        defer sub.deinit();
        const buf = try sub.toString();
        defer buf.deinit();
        //std.debug.print("{s}:{} \"{s}\"\n", .{@src().fn_name, @src().line, buf.items});
        try expectEqualStrings(buf.items, " se fu");
    }

    {
        const sub = try main_str.substring(1, 3);
        defer sub.deinit();
        const buf = try sub.toString();
        defer buf.deinit();
        //std.debug.print("{s}:{} \"{s}\"\n", .{@src().fn_name, @src().line, buf.items});
        try expectEqualStrings(buf.items, "osé");
    }
    {
        const sub = try main_str.substring(8, -1);
        defer sub.deinit();
        const buf = try sub.toString();
        defer buf.deinit();
        //std.debug.print("{s}:{} \"{s}\"\n", .{@src().fn_name, @src().line, buf.items});
        try expectEqualStrings(buf.items, "fué");
    }
}

test "Equals" {
    var ctx = try Context.New(alloc);
    defer ctx.deinit();
    const c_str = "my file.desktop";
    const filename = try String.From(alloc, ctx, c_str);
    defer filename.deinit();
    const ext = ".desKtop";
    {
        const result = filename.endsWith(ctx, ext, String.CaseSensitive.Yes);
        try expect(!result);
        //std.debug.print("\"{s}\" ends with {s}(cs.Yes): {}\n", .{ c_str, ext, result });
    }
    {
        const result = filename.endsWith(ctx, ext, String.CaseSensitive.No);
        try expect(result);
        //std.debug.print("\"{s}\" ends with {s}(cs.No): {}\n", .{ c_str, ext, result });
    }

    const str1 = try String.From(alloc, ctx, ".desktop");
    defer str1.deinit();
    const str2 = try String.From(alloc, ctx, ".desKtop");
    defer str2.deinit();
    const cs = str1.equalsStr(ctx, str2, String.CaseSensitive.Yes);
    const ncs = str1.equalsStr(ctx, str2, String.CaseSensitive.No);
    //std.debug.print("'{}' equals '{}': CaseSensitive: {}, NonCaseSensitive: {}\n", .{ str1, str2, cs, ncs });
    try expect (!cs and ncs);
}

test "FindInsertRemove" {
    // const chinese = try String.From(alloc, "违法和不良信息举报电话");
    // defer chinese.deinit();
    // try chinese.printGraphemes(std.debug);
    var ctx = try Context.New(alloc);
    defer ctx.deinit();
    const str = "<human><name>Jos\u{65}\u{301}</name><age>27</age></human>\u{65}\u{301}";
    const haystack = try String.From(alloc, ctx, str);
    defer haystack.deinit();
    const cs = String.CaseSensitive.No  ;
    {
        const index = haystack.indexOf(ctx, "<human>", 0, cs) orelse return String.Error.NotFound;
        try expect(index.cp == 0 and index.gr == 0);
        const index2 = haystack.indexOf(ctx, "</human>", 0, cs) orelse return String.Error.NotFound;
        try expect(index2.cp == 38 and index2.gr == 37);
    }

    {
        const str_to_find = try String.toCodePoints(alloc, "</age>");
        defer str_to_find.deinit();
        const index = haystack.indexOf3(ctx, str_to_find.items, haystack.graphemeAddress(0), cs)
            orelse return String.Error.NotFound;
        try expect(index.cp == 32 and index.gr == 31);
    }
    
    const initial_str = "Jos\u{65}\u{301} no se va";
    {
        var s = try String.From(alloc, ctx, initial_str);
        defer s.deinit();
        try s.remove(ctx, "os\u{65}\u{301}");
        const buf = try s.toString();
        defer buf.deinit();
        try expectEqualStrings(buf.items, "J no se va");
    }
    {
        var s = try String.From(alloc, ctx, initial_str);
        defer s.deinit();
        const needles = "no";
        const from = s.indexOf(ctx, needles, 0, cs);
        try s.removeByIndex(from, 200);
        const buf = try s.toString();
        defer buf.deinit();
        try expectEqualStrings(buf.items, "Jos\u{65}\u{301} ");
    }
    {
        var s = try String.From(alloc, ctx, initial_str);
        defer s.deinit(); 
        try s.insert(ctx, s.At(5), "举报");
        const buf = try s.toString();
        defer buf.deinit();
        try expectEqualStrings("José 举报no se va", buf.items);
    }
    {
        var s = try String.From(alloc, ctx, initial_str);
        defer s.deinit();
        const start_from = s.indexOf(ctx, "no", 0, cs);
        try s.replace(ctx, start_from, 2, "si\u{301}");
        const buf = try s.toString();
        defer buf.deinit();
        try expectEqualStrings("José sí se va", buf.items);
    }
    {
        var s = try String.From(alloc, ctx, initial_str);
        defer s.deinit();
        var jo_str = try String.From(alloc, ctx, "JO");
        defer jo_str.deinit();
        try expect(s.startsWithStr(ctx, jo_str, String.CaseSensitive.Yes) == false);
        try expect(s.startsWithStr(ctx, jo_str, String.CaseSensitive.No));

        var foo = try String.From(alloc, ctx, "Foo");
        defer foo.deinit();
        const foo_buf = try foo.toString();
        defer foo_buf.deinit();

        try expect(s.startsWithStr(ctx, foo, String.CaseSensitive.Yes) == false);
        
        const str_end = "se va";
        try expect(s.endsWith(ctx, str_end, String.CaseSensitive.Yes));
        try expect(s.endsWithStr(ctx, foo, String.CaseSensitive.Yes) == false);
    }
}

test "Split" {
    var ctx = try Context.New(alloc);
    defer ctx.deinit();
    const main_str = try String.From(alloc, ctx, JoseStr);
    defer main_str.deinit();
    // the next 2 functions help the developer to visually dissect a string:
    try main_str.printGraphemes(ctx, std.debug, theme);
    try main_str.printCodepoints(ctx, std.debug, theme);

    // split(..) returns !ArrayList(String)
    const words = try main_str.split(ctx, " ", CaseSensitive.Yes, KeepEmptyParts.No);
    defer {
        for (words.items) |item| {
            item.deinit();
        }
        words.deinit();
    }

    const correct = [_][]const u8 {"Jos\u{65}\u{301}", "se",
    "fu\u{65}\u{301}", "a", "Sevilla", "sin", "pararse"};
    try expect(words.items.len == correct.len);
    for (words.items, correct) |a, b| {
        try expect(a.equals(ctx, b, String.CaseSensitive.Yes));
    }

    //============= another test
    const hello_world = try String.From(alloc, ctx, "Hello, World!");
    defer hello_world.deinit();
    const hello_split = try hello_world.split(ctx, " ", CaseSensitive.Yes, KeepEmptyParts.No);
    defer {
        for(hello_split.items) |s| {
            s.deinit();
        }
        hello_split.deinit();
    }

    const correct2 = [_][]const u8 {"Hello,", "World!"};
    for (hello_split.items, correct2) |l, r| {
        try expect(l.equals(ctx, r, CaseSensitive.Yes));
    }

    const start_from: usize = 0;
    const at = hello_world.indexOf(ctx, "lo", start_from, CaseSensitive.Yes);
    if (at) |index| {
        try expect(index.gr == 3); // .gr=grapheme, .cp=codepoint
    } else {
        std.debug.print("IndexOf \"lo\" not found", .{});
    }

    const sub = try hello_world.substring(3, 5);
    defer sub.deinit();
    try expect(sub.equals(ctx, "lo, W", CaseSensitive.Yes));

    const sub2 = try hello_world.substring(3, -1);
    defer sub2.deinit();
    try expect(sub2.equals(ctx, "lo, World!", CaseSensitive.Yes));

    //============= another test
    const empty_str = try String.From(alloc, ctx, "Foo  Bar");
    defer empty_str.deinit();
    const empty_arr = try empty_str.split(ctx, " ", CaseSensitive.Yes, KeepEmptyParts.Yes);
    defer {
        for (empty_arr.items) |item| {
            item.deinit();
        }
        empty_arr.deinit();
    }

    const correct3 = [_][]const u8 {"Foo", "", "Bar"};
    try expect(empty_arr.items.len == correct3.len);
    for (empty_arr.items, correct3) |str_obj, char_arr| {
        try expect(str_obj.equals(ctx, char_arr, CaseSensitive.Yes));
    }

}

test "To Upper, To Lower" {
    var ctx = try Context.New(alloc);
    defer ctx.deinit();

    const normal = [_][]const u8 {"Hello, World!", "Привет!", "Jos\u{65}\u{301}"};
    const upper = [_][]const u8 {"HELLO, WORLD!", "ПРИВЕТ!", "JOS\u{45}\u{301}"};
    const lower = [_][]const u8 {"hello, world!", "привет!", "jos\u{65}\u{301}"};

    for (normal, upper, lower) |n, u, l| {
        var str = try String.From(alloc, ctx, n);
        defer str.deinit();
        try str.toUpper(ctx);
        try expect(str.equals(ctx, u, CaseSensitive.Yes));
        try str.toLower(ctx);
        try expect(str.equals(ctx, l, CaseSensitive.Yes));
    }
}

test "Case Fold" {

}
