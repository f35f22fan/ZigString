const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const expectError = std.testing.expectError;
var out = std.io.getStdOut().writer();

const String = @import("String.zig").String;
const CodePoint = String.CodePoint;
const Index = String.Index;
const ziglyph = @import("ziglyph");
const letter = ziglyph.letter;
const number = ziglyph.number;
const Grapheme = ziglyph.Grapheme;
const GraphemeIterator = Grapheme.GraphemeIterator;

const zigstr = @import("zigstr");
const io = @import("io.zig");

const Error = error {
    BadArg,
    NotFound,
};
const TimeExt = "mc";
inline fn getTime() i128 {
    return std.time.microTimestamp();
}

fn FindOneSimd(a: Allocator, haystack: String, needle: CodePoint,
    from: usize, correct: ?usize, comptime depth: u16) !usize {
    const start_time = getTime();
    const result = haystack.findOneSimd(needle, from, depth);
    const done_in = getTime() - start_time;

    var buf = try String.utf8_from_cp(a, needle);
    defer buf.deinit();
    const print_color = if (correct == null or correct == result) COLOR_DEFAULT else COLOR_RED;
    try out.print("{s}FoundAt={?}, From={}, needles=\"{s}\", Time={}{s} [{s}]{s}\n",
        .{ print_color, result, from, buf.items, done_in, TimeExt, @src().fn_name, COLOR_DEFAULT });
    
    return if (result) |t| t else Error.NotFound;
}

fn FindOneLinear(a: Allocator, haystack: String, needle: CodePoint) !String.Index {
    const start_time = getTime();
    const result = std.mem.indexOfScalar(CodePoint, haystack.codepoints.items, needle);
    const done_in = getTime() - start_time;
    var buf = try String.utf8_from_cp(a, needle);
    defer buf.deinit();
    try out.print("{s}: FoundAt={?}, T={}{s}, needle=\"{s}\"\n",
        .{@src().fn_name, result, done_in, TimeExt, buf.items });
    
    return result;
}

fn FindManySimd(a: Allocator, haystack: String, needles: String.CodePointSlice,
from: ?Index, comptime depth: u16, correct: ?usize) !String.Index {
    var buf = try String.utf8_from_slice(a, needles);
    defer buf.deinit();

    const start_time = getTime();
    const result = haystack.findManySimd(needles, from, depth) orelse {
        try out.print("{s} not found '{s}' from={?}, haystack.cp_count={}\n",
        .{@src().fn_name, buf.items, from, haystack.codepoints.items.len});
        return Error.NotFound;
    };
    const done_in = getTime() - start_time;
    
    const print_color = if (correct == null or correct == result.gr) COLOR_DEFAULT else COLOR_RED;
    try out.print("{s}FoundAt={?}, From={?}, needles=\"{s}\", Time={}{s} [{s}]{s}\n",
    .{ print_color, result, from, buf.items, done_in, TimeExt, @src().fn_name, COLOR_DEFAULT });
    
    return result;
}

fn FindManyLinear(a: Allocator, haystack: String, needles: String.CodePointSlice, from: ?Index,
    correct: ?usize) !String.Index {
    const start_time = getTime();
    const result = haystack.findManyLinear(needles, from) orelse return Error.NotFound;
    const done_in = getTime() - start_time;

    var buf = try String.utf8_from_slice(a, needles);
    defer buf.deinit();
    const print_color = if (correct == null or correct == result.gr) COLOR_DEFAULT else COLOR_RED;
    try out.print("{s}FoundAt={?}, From={?}, needles=\"{s}\", Time={}{s} [{s}]{s}\n",
    .{ print_color, result, from, buf.items, done_in, TimeExt, @src().fn_name, COLOR_DEFAULT });
    
    return result;
}

fn FindManyLinearZigstr(a: Allocator, haystack: []const u8, needles: []const u8, from: usize,
    correct: ?usize) !usize {
    const start_t = getTime();
    var str = try zigstr.fromConstBytes(a, haystack[from..]);
    defer str.deinit();
    const done_t = getTime() - start_t;

    const start_time = getTime();
    var result = str.indexOf(needles) orelse return Error.NotFound;
    result += from;
    const done_in = getTime() - start_time;

    const print_color = if (correct == null or correct == result) COLOR_DEFAULT else COLOR_BLUE;
    try out.print("{s}FoundAt={?}, From={}, needles=\"{s}\", Time={}{s}, StrInit={}{s} [{s}]{s}\n\n",
        .{ print_color, result, from, needles, done_in, TimeExt, done_t, TimeExt, @src().fn_name, COLOR_DEFAULT });

    return result;
}

fn FindTagValue(a: Allocator) !void {
    const str = "<human><age>27</age><name>Jos\u{65}\u{301}</name></human>";
    const haystack = try String.From(a, str);
    defer haystack.deinit();
    
    if (false) {
        const index = haystack.indexOf("<age>", 0);
        try out.print("{s}() indexOf: {?}\n\n", .{@src().fn_name, index});
    
        const needles = try String.toCodePoints(a, "</age>");
        defer needles.deinit();
        const index2 = haystack.indexOf2(needles.items, haystack.graphemeAddress(0));
        try out.print("{s}() indexOf2: {?}\n\n", .{@src().fn_name, index2});
    }

    if (true) {
        const initial_str = "Jos\u{65}\u{301} no se va";
        {
            var s = try String.From(a, initial_str);
            defer s.deinit();
            const needles = "va";
            const from = s.indexOf(needles, null);
            try s.remove(from, 1);
            const buf = try s.toString();
            defer buf.deinit();
            try out.print("{s}() after remove('{s}'): \"{s}\"\n\n",
            .{@src().fn_name, needles, buf.items});
        }
        {
            var s = try String.From(a, initial_str);
            defer s.deinit();
            const needles = "OK";
            const from = s.indexOf(needles, null);
            try s.remove(from, 1);
            const buf = try s.toString();
            defer buf.deinit();
            try out.print("{s}() after remove('{s}'): \"{s}\"\n\n",
            .{@src().fn_name, needles, buf.items});
        }
        {
            var s = try String.From(a, initial_str);
            defer s.deinit();
            try s.remove(s.seek(5), 1);
            const buf = try s.toString();
            defer buf.deinit();
            try out.print("{s}() after remove(): \"{s}\"\n\n", .{@src().fn_name, buf.items});
        }
        {
            var s = try String.From(a, initial_str);
            defer s.deinit();
            try s.insert(s.seek(5), "WOW!");
            const buf = try s.toString();
            defer buf.deinit();
            try out.print("{s}() after insert(): \"{s}\"\n\n", .{@src().fn_name, buf.items});
        }
        {
            var s = try String.From(a, initial_str);
            defer s.deinit();
            const start_from = s.indexOf("no", null);
            try s.replace(start_from, 2, "si\u{301}");
            const buf = try s.toString();
            defer buf.deinit();
            try out.print("{s}() after replace(): \"{s}\"\n\n", .{@src().fn_name, buf.items});
        }
        {
            var s = try String.From(a, initial_str);
            defer s.deinit();
            
            var sub = try String.From(a, "Jo");
            defer sub.deinit();

            const buf = try sub.toString();
            defer buf.deinit();

            try out.print("{s}() startsWith('{s}'): \"{}\"\n\n",
            .{@src().fn_name, buf.items, s.startsWithStr(sub)});

            var foo = try String.From(a, "Foo");
            defer foo.deinit();
            const foo_buf = try foo.toString();
            defer foo_buf.deinit();

            try out.print("{s}() startsWith('{s}'): \"{}\"\n\n",
            .{@src().fn_name, foo_buf.items, s.startsWithStr(foo)});

            const str_end = "se va";

            try out.print("{s}() endsWith('{s}'): \"{!}\"\n\n",
            .{@src().fn_name, str_end, s.endsWith(str_end)});

            try out.print("{s}() endsWith('{s}'): \"{}\"\n\n",
            .{@src().fn_name, foo_buf.items, s.endsWithStr(foo)});
        }
    }
    
    try out.print("\n", .{});
}

fn FindBackwards(a: Allocator) !void {
    const str = "<human><age>27</age><name>Jos\u{65}\u{301}</name></human>";
    const haystack = try String.From(a, str);
    defer haystack.deinit();
    try haystack.printCodePoints();

    {
        const start_time = getTime();
        const needles_raw = "\u{65}\u{301}";
        const from: ?Index = haystack.fromEnd(14);
        const result = haystack.lastIndexOf(needles_raw, from);
        const done_in = getTime() - start_time;
        
        try out.print("findManySimdFromEnd() FoundAt={?}, From={?}, needles=\"{s}\", Time={}{s} [{s}]{s}\n",
        .{ result, from, needles_raw, done_in, TimeExt, @src().fn_name, COLOR_DEFAULT });
    
    }

    if (false) { // Being implemented:
        var s = try String.From(a, str);
        try s.trim();
    }
    
}

pub fn main() !u8 {
    const a = std.heap.page_allocator;
    const JoseStr = "Jos\u{65}\u{301} se fu\u{65}\u{301} a Sevilla sin pararse";

    //try FindTagValue(a);

    try FindBackwards(a);

    if (true) {
        var s = try String.From(a, JoseStr);
        try s.append("[ADDITIONAL STRING]");
        var buf = try s.toString();
        defer buf.deinit();
        try out.print("String.Append(gr={}) :\"{s}\"\n",
        .{s.grapheme_count, buf.items});

        
    }

    if (false) {
        const haystack = try String.From(a, JoseStr);
        const needle = try String.toCodePoints(a, "s");
        defer needle.deinit();
        const cp = needle.items[0];
        const vec_len: u16 = 32;
        const found = try FindOneSimd(a, haystack, cp, 0, 2, vec_len);
        _ = found;
    }

    if (false) {
        const needles: String.CodePointSlice = &[_]CodePoint{ 's', 'i' };
        const needles_raw = "si";
        const from =    [_]usize{0};
        const correct = [_]usize{22};
        try test_find_index(a, JoseStr, needles, needles_raw, &from, &correct);
    }

    if (false) {
        const needles: String.CodePointSlice = &[_]CodePoint{ 's', 'e' };
        const needles_raw = "se";
        const from =    [_]usize{0, 2, 33};
        const correct = [_]usize{5, 5, 31};
        try test_find_index(a, JoseStr, needles, needles_raw, &from, &correct);
    }

    if (false) {
        const raw_str = try io.readFile(a, "/home/fox/input/content.xml");
        defer a.free(raw_str);
        const needles_raw = "И если нефилим действительно были теми «богами»";
        // "Третья (фронтальная) группа явно состояла из мужских";
        const needles = try String.toCodePoints(a, needles_raw);
        defer needles.deinit();
        const from = [_]usize{0};
        try test_find_index(a, raw_str, needles.items, needles_raw, &from, null);
    }

    return 0;
}

pub fn test_find_index(a: Allocator, raw_str: []const u8, needles: String.CodePointSlice,
    needles_raw: []const u8, froms: []const usize, answers: ?[]const usize) !void {
    { // short string
        const short_string_len: usize = 255;
        if (raw_str.len <= short_string_len) {
            try out.print("NEW TEST, string.len={} bytes: '{s}'\n", .{ raw_str.len, raw_str });
        } else {
            try out.print("NEW TEST, string.len={} bytes\n", .{ raw_str.len});
        }
        const start_time = getTime();
        var haystack: String = try String.From(a, raw_str);
        defer haystack.deinit();
        const done_in = getTime() - start_time;
        try out.print("String(graphemes={}, cp={}) init done in {}{s}\n",
            .{haystack.grapheme_count, haystack.codepoints.items.len, done_in, TimeExt});
        if (raw_str.len <= short_string_len) {
            try haystack.printCodePoints();
        }

        const depth: u16 = 32;
       
        for (0..froms.len) |i| {
            const correct = if (answers) |ans| ans[i] else null;
            //_ = depth;
            const from = froms[i];
            const from_index = haystack.seek(from);
            _ = try FindManySimd(a, haystack, needles, from_index, depth, correct);
            _ = try FindManyLinear(a, haystack, needles, from_index, correct);
            //_ = needles_raw;
            _ = try FindManyLinearZigstr(a, raw_str, needles_raw, from, correct);
        }

        // try expectError(String.Error.NotFound, FindManySimd(a, haystack, needles, 36, depth));
        // try expectError(String.Error.NotFound, FindManyLinear(a, haystack, needles, 36));
    }
}

const COLOR_BLUE = "\x1B[34m";
const COLOR_DEFAULT = "\x1B[0m";
const COLOR_GREEN = "\x1B[32m";
const COLOR_RED = "\x1B[0;91m";
const COLOR_YELLOW = "\x1B[93m";
const COLOR_MAGENTA = "\x1B[35m";
const BLINK_START = "\x1B[5m";
const BLINK_END = "\x1B[25m";
const BOLD_START = "\x1B[1m";
const BOLD_END = "\x1B[0m";
const UNDERLINE_START = "\x1B[4m";
const UNDERLINE_END = "\x1B[0m";