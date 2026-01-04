const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const alloc = std.testing.allocator;

// const zigstr = @import("zigstr");
const io = @import("io.zig");
const mtl = @import("mtl.zig");

const Normalize = @import("Normalize");
const CaseFold = @import("CaseFold");
const ScriptsData = @import("ScriptsData");

const String = @import("String.zig").String;
const CaseSensitive = String.CaseSensitive;
const Codepoint = String.Codepoint;
const ConstCpSlice = String.ConstCpSlice;
const CpSlice = String.CpSlice;
const Context = String.Context;

const Error = String.Error;
const Index = String.Index;
const KeepEmptyParts = String.KeepEmptyParts;

const JoseStr = "Jos\u{65}\u{301} se fu\u{65}\u{301} a Sevilla sin pararse";
const theme = String.Theme.Dark;

const TimeExt = "mc";
inline fn getTime() i128 {
    return std.time.microTimestamp();
}

fn getFgColor(result: usize, correct: ?usize) []const u8 {
    if (correct) |c| {
        return if (result == c) mtl.COLOR_DEFAULT else mtl.COLOR_RED;
    }
    return mtl.COLOR_BLUE;
}

fn FindOneSimd(haystack: String, needle: Codepoint, from: usize, correct: ?usize, comptime depth: u16) !usize {
    const start_time = getTime();
    const result = haystack.findOneSimd(needle, from, depth);
    const done_in = getTime() - start_time;
    const print_color = getFgColor(result, correct);
    mtl.debug(@src(), "{s}FoundAt={?}, From={}, Time={}{s}", .{ print_color, result, from, done_in, TimeExt });

    return if (result) |t| t else Error.NotFound;
}

fn FindOneLinear(haystack: String, needle: Codepoint) !String.Index {
    const start_time = getTime();
    const result = std.mem.indexOfScalar(Codepoint, haystack.codepoints.items, needle);
    const done_in = getTime() - start_time;
    mtl.debug(@src(), "FoundAt={?}, T={}{s}", .{ result, done_in, TimeExt });

    return result;
}

fn FindManySimd(haystack: String, needles: ConstCpSlice, from: ?Index, comptime depth: u16, correct: ?usize) !String.Index {
    const start_time = getTime();
    const result = haystack.findManySimd(needles, from, depth) orelse {
        var buf = try String.utf8_from_slice(alloc, needles);
        defer buf.deinit(alloc);
        mtl.debug(@src(), "Not found '{s}' from={?f}, haystack.cp_count={}", .{ buf.items, from, haystack.size_cp() });
        if (haystack.size() < 50) {
            mtl.debug(@src(), "Haystack: {f}", .{haystack});
        }
        return Error.NotFound;
    };
    const done_in = getTime() - start_time;
    const print_color = getFgColor(result.gr, correct);
    mtl.debug(@src(), "{s}FoundAt={f}, From={?f}, Time={}{s}", .{ print_color, result, from, done_in, TimeExt });

    return result;
}

fn FindManyLinear(haystack: String, needles: ConstCpSlice, from: ?Index, correct: ?usize) !String.Index {
    const start_time = getTime();
    const result = haystack.findManyLinear(needles, from, CaseSensitive.Yes) orelse return Error.NotFound;
    const done_in = getTime() - start_time;
    const print_color = getFgColor(result.gr, correct);
    mtl.debug(@src(), "{s}FoundAt={f}, From={?f}, Time={}{s}", .{ print_color, result, from, done_in, TimeExt });

    return result;
}

fn FindBackwards() !void {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const str = "<human><age>27</age><name>Jos\u{65}\u{301}</name></human>";
    const haystack = try String.From(str);
    defer haystack.deinit();

    {
        const start_time = getTime();
        const needles_raw = "\u{65}\u{301}";
        const from: ?Index = haystack.fromEnd(14);
        const result = haystack.lastIndexOf(needles_raw, from);
        const done_in = getTime() - start_time;

        mtl.debug(@src(), "findManySimdFromEnd() FoundAt={f?}, From={f?}, needles=\"{s}\", Time={}{s}", .{ result, from, needles_raw, done_in, TimeExt });
    }
}

pub fn test_find_index(raw_str: []const u8, needles: ConstCpSlice, froms: []const usize, answers: ?[]const usize) !void {
    std.debug.print("=" ** 70 ++ "\n", .{});
    const short_string_len: usize = 255;
    var needles_buf = try String.utf8_from_slice(alloc, needles);
    defer needles_buf.deinit(alloc);
    mtl.debug(@src(), "needles_count=\"{s}{s}\"", .{ mtl.COLOR_GREEN, needles_buf.items });
    if (raw_str.len <= short_string_len) {
        mtl.debug(@src(), "raw_str.len={} bytes: '{s}'", .{ raw_str.len, raw_str });
    } else {
        mtl.debug(@src(), "raw_str.len={} bytes", .{raw_str.len});
    }
    const start_time = getTime();
    var haystack = try String.New(raw_str);
    defer haystack.deinit();
    const done_in = getTime() - start_time;
    mtl.debug(@src(), "String(graphemes={}, cp={}) init done in {}{s}\n", .{ haystack.size(), haystack.size_cp(), done_in, TimeExt });
    if (raw_str.len <= short_string_len) {
        try haystack.printGraphemes(@src());
        try haystack.printCodepoints(@src());
    }

    const depth: u16 = 32;

    for (0..froms.len) |i| {
        const correct = if (answers) |ans| ans[i] else null;
        const from = froms[i];
        const from_i = haystack.findIndex(from);
        _ = try FindManySimd(haystack, needles, from_i, depth, correct);
        _ = try FindManyLinear(haystack, needles, from_i, correct);
        // _ = try FindManyLinearZigstr(raw_str, needles_raw, from, correct);
    }
}

test "From File" {
    try String.Init(alloc);
    defer String.Deinit();

    const path = try io.getHomeUtf8(alloc, "/Documents/content.xml");
    defer path.deinit();
    var file_contents = try io.readFile(alloc, path);
    defer file_contents.deinit(alloc);
    const needles_raw = "CONCAT(&quot;EC.TYPE=&quot;;[SLAVE1_CAN.G181]))\"";
    // "Это подтверждается разговором арестованного Иисуса";
    var needles = try String.toCodepoints(alloc, needles_raw);
    defer needles.deinit(alloc);
    const from = [_]usize{0};
    const correct = [_]usize{7753055};
    try test_find_index(file_contents.items[0..], needles.items, from[0..], correct[0..]);
}

test "Speed test 2" {
    try String.Init(alloc);
    defer String.Deinit();

    const needles = [_]Codepoint{ 's', 'e' };
    const from = [_]usize{ 0, 2, 31 };
    const correct = [_]usize{ 5, 5, 31 };
    try test_find_index(JoseStr, &needles, &from, &correct);
}
