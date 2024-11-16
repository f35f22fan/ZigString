const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const alloc = std.testing.allocator;

const zigstr = @import("zigstr");
const io = @import("io.zig");

const CaseData = @import("CaseData");

const String = @import("String.zig").String;
const CaseSensitive = String.CaseSensitive;
const Codepoint = String.Codepoint;
const CodepointSlice = String.CodepointSlice;
const CpSlice = String.CpSlice;
const Error = String.Error;
const Index = String.Index;
const KeepEmptyParts = String.KeepEmptyParts;

const JoseStr = "Jos\u{65}\u{301} se fu\u{65}\u{301} a Sevilla sin pararse";
const theme = String.Theme.Dark;

const COLOR_BLUE = "\x1B[34m";
const COLOR_DEFAULT = "\x1B[0m";
const COLOR_GREEN = "\x1B[32m";
const COLOR_RED = "\x1B[0;91m";
const COLOR_YELLOW = "\x1B[93m";
const COLOR_MAGENTA = "\x1B[35m";
const COLOR_CYAN = "\x1B[36m";
const COLOR_BLACK = "\x1B[38;5;16m";
const BLINK_START = "\x1B[5m";
const BLINK_END = "\x1B[25m";
const BOLD_START = "\x1B[1m";
const BOLD_END = "\x1B[0m";
const UNDERLINE_START = "\x1B[4m";
const UNDERLINE_END = "\x1B[0m";

const TimeExt = "mc";
inline fn getTime() i128 {
    return std.time.microTimestamp();
}

fn getFgColor(result: usize, correct: ?usize) []const u8 {
    if (correct) |c| {
        return if (result == c) COLOR_DEFAULT else COLOR_RED;
    }
    return COLOR_BLUE;
}

fn FindOneSimd(haystack: String, needle: Codepoint, from: usize, correct: ?usize, comptime depth: u16) !usize {
    const start_time = getTime();
    const result = haystack.findOneSimd(needle, from, depth);
    const done_in = getTime() - start_time;
    const print_color = getFgColor(result, correct);
    std.debug.print("{s}FoundAt={?}, From={}, Time={}{s} [{s}]{s}\n", .{ print_color, result, from, done_in, TimeExt, @src().fn_name, COLOR_DEFAULT });

    return if (result) |t| t else Error.NotFound;
}

fn FindOneLinear(haystack: String, needle: Codepoint) !String.Index {
    const start_time = getTime();
    const result = std.mem.indexOfScalar(Codepoint, haystack.codepoints.items, needle);
    const done_in = getTime() - start_time;
    std.debug.print("{s}: FoundAt={?}, T={}{s}\n", .{ @src().fn_name, result, done_in, TimeExt});

    return result;
}

fn FindManySimd(haystack: String, needles: CpSlice, from: ?Index, comptime depth: u16, correct: ?usize) !String.Index {
    const start_time = getTime();
    const result = haystack.findManySimd(needles, from, depth) orelse {
        const buf = try String.utf8_from_slice(alloc, needles);
        defer buf.deinit();
        std.debug.print("{s} not found '{s}' from={?}, haystack.cp_count={}\n", .{ @src().fn_name, buf.items, from, haystack.codepoints.items.len });
        return Error.NotFound;
    };
    const done_in = getTime() - start_time;
    const print_color = getFgColor(result.gr, correct);
    std.debug.print("{s}FoundAt={?}, From={?}, Time={}{s} [{s}]{s}\n", .{ print_color, result, from, done_in, TimeExt, @src().fn_name, COLOR_DEFAULT });

    return result;
}

fn FindManyLinear(haystack: String, needles: CpSlice, from: ?Index, correct: ?usize) !String.Index {
    const start_time = getTime();
    const result = haystack.findManyLinear(needles, from, CaseSensitive.Yes) orelse return Error.NotFound;
    const done_in = getTime() - start_time;
    const print_color = getFgColor(result.gr, correct);
    std.debug.print("{s}FoundAt={?}, From={?}, Time={}{s} [{s}]{s}\n", .{ print_color, result, from, done_in, TimeExt, @src().fn_name, COLOR_DEFAULT });

    return result;
}

fn FindManyLinearZigstr(haystack: []const u8, needles: []const u8, from: usize, correct: ?usize) !usize {
    const start_t = getTime();
    const cd = try zigstr.Data.init(alloc);
    defer cd.deinit();
    var str = try zigstr.fromConstBytes(alloc, &cd, haystack[from..]);
    defer str.deinit();
    const done_t = getTime() - start_t;
    const start_time = getTime();
    var result = str.indexOf(needles) orelse return Error.NotFound;
    result += from;
    const done_in = getTime() - start_time;
    const print_color = getFgColor(result, correct);
    std.debug.print("{s}FoundAt={?}, From={}, Time={}{s}, StrInit={}{s}, [{s}]{s}\n\n",
    .{ print_color, result, from, done_in, TimeExt, done_t, TimeExt, @src().fn_name, COLOR_DEFAULT });

    return result;
}

fn FindBackwards() !void {
    const str = "<human><age>27</age><name>Jos\u{65}\u{301}</name></human>";
    const haystack = try String.From(alloc, str);
    defer haystack.deinit();

    {
        const start_time = getTime();
        const needles_raw = "\u{65}\u{301}";
        const from: ?Index = haystack.fromEnd(14);
        const result = haystack.lastIndexOf(needles_raw, from);
        const done_in = getTime() - start_time;

        std.debug.print("findManySimdFromEnd() FoundAt={?}, From={?}, needles=\"{s}\", Time={}{s} [{s}]{s}\n", .{ result, from, needles_raw, done_in, TimeExt, @src().fn_name, COLOR_DEFAULT });
    }
}

pub fn test_find_index(a: Allocator, raw_str: []const u8, needles: CpSlice, needles_raw: []const u8, froms: []const usize, answers: ?[]const usize) !void {
    std.debug.print("="**70++"\n", .{});
    const short_string_len: usize = 255;
    const needles_buf = try String.utf8_from_slice(alloc, needles);
    defer needles_buf.deinit();
    std.debug.print("{s}(): needles=\"{s}{s}{s}\"\n", .{@src().fn_name, COLOR_GREEN, needles_buf.items, COLOR_DEFAULT});
    if (raw_str.len <= short_string_len) {
        std.debug.print("raw_str.len={} bytes: '{s}'\n", .{ raw_str.len, raw_str });
    } else {
        std.debug.print("raw_str.len={} bytes\n", .{raw_str.len});
    }
    const start_time = getTime();
    var haystack: String = try String.From(a, raw_str);
    defer haystack.deinit();
    const done_in = getTime() - start_time;
    std.debug.print("String(graphemes={}, cp={}) init done in {}{s}\n\n", .{ haystack.grapheme_count, haystack.codepoints.items.len, done_in, TimeExt });
    if (raw_str.len <= short_string_len) {
        try haystack.printGraphemes(std.debug, theme);
        try haystack.printCodepoints(std.debug, theme);
    }

    const depth: u16 = 32;

    for (0..froms.len) |i| {
        const correct = if (answers) |ans| ans[i] else null;
        const from = froms[i];
        const from_i = haystack.graphemeAddress(from);
        _ = try FindManySimd(haystack, needles, from_i, depth, correct);
        _ = try FindManyLinear(haystack, needles, from_i, correct);
        _ = try FindManyLinearZigstr(raw_str, needles_raw, from, correct);
    }
}

test "From File" {
    const raw_str = try io.readFile(alloc, "/home/fox/Documents/content.xml");
    defer alloc.free(raw_str);
    const needles_raw = "Это подтверждается разговором арестованного Иисуса";
    const needles = try String.toCodePoints(alloc, needles_raw);
    defer needles.deinit();
    const from = [_]usize{0};
    const correct = [_]usize{966438};
    try test_find_index(alloc, raw_str, needles.items, needles_raw, from[0..], correct[0..]);
}

test "Speed test 2" {
    const needles = [_]Codepoint{ 's', 'e' };
    const needles_raw = "se";
    const from = [_]usize{ 0, 2, 31 };
    const correct = [_]usize{ 5, 5, 31 };
    try test_find_index(alloc, JoseStr, &needles, needles_raw, &from, &correct);
}

