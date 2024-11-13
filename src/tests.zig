const std = @import("std");
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const alloc = std.testing.allocator;

const String = @import("String.zig").String;
const Index = String.Index;
const Codepoint = String.Codepoint;
// Don't change this string, many tests depend on it:
const JoseStr = "Jos\u{65}\u{301} se fu\u{65}\u{301} a Sevilla sin pararse";
const theme = String.Theme.Dark;

test "Append Test" {
    const additional = "[Ещё]";
    var main_str = try String.From(alloc, JoseStr);
    defer main_str.deinit();
    const chained = JoseStr ++ additional;
    try main_str.append(additional);
    var utf8_buf = try main_str.toString();
    defer utf8_buf.deinit();
    try expectEqualStrings(utf8_buf.items, chained);
}

test "Get Grapheme Address" {
    const main_str = try String.From(alloc, JoseStr);
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
    const trim_left_str = "  \t Привет!";
    var main_str = try String.From(alloc, trim_left_str);
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
        var trim_nothing_str = try String.From(alloc, orig_str);
        defer trim_nothing_str.deinit();
        try trim_nothing_str.trimLeft();
        const buf = try trim_nothing_str.toString();
        defer buf.deinit();
        // std.debug.print("{s}(): \"{s}\" => \"{s}\"\n", .{@src().fn_name, orig_str, buf.items});
        try expectEqualStrings(orig_str, buf.items);
    }
}

test "Trim Right" {
    const trim_right_str = "Привет! \t  ";
    var main_str = try String.From(alloc, trim_right_str);
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
        var str = try String.From(alloc, orig_str);
        defer str.deinit();
        try str.trimRight();
        const buf = try str.toString();
        defer buf.deinit();
        // std.debug.print("{s}(): \"{s}\" => \"{s}\"\n", .{@src().fn_name, orig_str, buf.items});
        try expectEqualStrings(orig_str, buf.items);
    }
}

test "Substring" {
    const main_str = try String.From(alloc, "Jos\u{65}\u{301} se fu\u{65}\u{301}");
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
    const c_str = "my file.desktop";
    const filename = try String.From(alloc, c_str);
    defer filename.deinit();
    const ext = ".desKtop";
    {
        const result = filename.endsWith(ext, String.CaseSensitive.Yes);
        try expect(!result);
        //std.debug.print("\"{s}\" ends with {s}(cs.Yes): {}\n", .{ c_str, ext, result });
    }
    {
        const result = filename.endsWith(ext, String.CaseSensitive.No);
        try expect(result);
        //std.debug.print("\"{s}\" ends with {s}(cs.No): {}\n", .{ c_str, ext, result });
    }

    const str1 = try String.From(alloc, ".desktop");
    defer str1.deinit();
    const str2 = try String.From(alloc, ".desKtop");
    defer str2.deinit();
    const cs = str1.equalsStr(str2, String.CaseSensitive.Yes);
    const ncs = str1.equalsStr(str2, String.CaseSensitive.No);
    //std.debug.print("'{}' equals '{}': CaseSensitive: {}, NonCaseSensitive: {}\n", .{ str1, str2, cs, ncs });
    try expect (!cs and ncs);
}

test "FindInsertRemove" {
    // const chinese = try String.From(alloc, "违法和不良信息举报电话");
    // defer chinese.deinit();
    // try chinese.printGraphemes(std.debug);

    const str = "<human><name>Jos\u{65}\u{301}</name><age>27</age></human>\u{65}\u{301}";
    const haystack = try String.From(alloc, str);
    defer haystack.deinit();
    const cs = String.CaseSensitive.No  ;
    {
        const index = haystack.indexOf("<human>", 0, cs) orelse return String.Error.NotFound;
        try expect(index.cp == 0 and index.gr == 0);
        const index2 = haystack.indexOf("</human>", 0, cs) orelse return String.Error.NotFound;
        try expect(index2.cp == 38 and index2.gr == 37);
    }

    {
        const str_to_find = try String.toCodePoints(alloc, "</age>");
        defer str_to_find.deinit();
        const index = haystack.indexOf3(str_to_find.items, haystack.graphemeAddress(0), cs)
            orelse return String.Error.NotFound;
        try expect(index.cp == 32 and index.gr == 31);
    }
    
    const initial_str = "Jos\u{65}\u{301} no se va";
    {
        var s = try String.From(alloc, initial_str);
        defer s.deinit();
        try s.remove("os\u{65}\u{301}");
        const buf = try s.toString();
        defer buf.deinit();
        try expectEqualStrings(buf.items, "J no se va");
    }
    {
        var s = try String.From(alloc, initial_str);
        defer s.deinit();
        const needles = "no";
        const from = s.indexOf(needles, 0, cs);
        try s.removeByIndex(from, 200);
        const buf = try s.toString();
        defer buf.deinit();
        try expectEqualStrings(buf.items, "Jos\u{65}\u{301} ");
    }
    {
        var s = try String.From(alloc, initial_str);
        defer s.deinit(); 
        try s.insert(s.At(5), "举报");
        const buf = try s.toString();
        defer buf.deinit();
        try expectEqualStrings("José 举报no se va", buf.items);
    }
    {
        var s = try String.From(alloc, initial_str);
        defer s.deinit();
        const start_from = s.indexOf("no", 0, cs);
        try s.replace(start_from, 2, "si\u{301}");
        const buf = try s.toString();
        defer buf.deinit();
        try expectEqualStrings("José sí se va", buf.items);
    }
    {
        var s = try String.From(alloc, initial_str);
        defer s.deinit();
        var jo_str = try String.From(alloc, "JO");
        defer jo_str.deinit();
        try expect(s.startsWithStr(jo_str, String.CaseSensitive.Yes) == false);
        try expect(s.startsWithStr(jo_str, String.CaseSensitive.No));

        var foo = try String.From(alloc, "Foo");
        defer foo.deinit();
        const foo_buf = try foo.toString();
        defer foo_buf.deinit();

        try expect(s.startsWithStr(foo, String.CaseSensitive.Yes) == false);
        
        const str_end = "se va";
        try expect(s.endsWith(str_end, String.CaseSensitive.Yes));
        try expect(s.endsWithStr(foo, String.CaseSensitive.Yes) == false);
    }
}

test "Split" {
    const main_str = try String.From(alloc, JoseStr);
    defer main_str.deinit();
    try main_str.printGraphemes(std.debug, theme);
    const lines = try main_str.split(" ", String.CaseSensitive.Yes, String.KeepEmptyParts.No);
    defer {
        for (lines.items) |item| {
            item.deinit();
        }
        lines.deinit();
    }

    for (lines.items) |s| {
        try s.print(std.debug, theme, "Split string: ");
    }

    var correct = ArrayList(String).init(alloc);
    defer {
        for (correct.items) |item| {
            item.deinit();
        }
        correct.deinit();
    }
    try correct.append(try String.From(alloc, "Jos\u{65}\u{301}"));
    try correct.append(try String.From(alloc, "se"));
    try correct.append(try String.From(alloc, "fu\u{65}\u{301}"));
    try correct.append(try String.From(alloc, "a"));
    try correct.append(try String.From(alloc, "Sevilla"));
    try correct.append(try String.From(alloc, "sin"));
    try correct.append(try String.From(alloc, "pararse"));
    
    try expect(lines.items.len == correct.items.len);
    
    for (lines.items, correct.items) |a, b| {
        try expect(a.equalsStr(b, String.CaseSensitive.Yes));
    }
}