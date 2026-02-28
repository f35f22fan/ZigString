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
const Ctring = @import("Ctring.zig").Ctring;
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

fn FindManySimd(haystack: String, needles_raw: []const u8, from: ?Index, comptime depth: u16, correct: ?usize) !String.Index {
    var needles = try String.toCodepoints(alloc, needles_raw);
    defer needles.deinit(alloc);
    const start_time = getTime();
    const result = haystack.findManySimd(needles.items, from, depth) orelse {
        mtl.debug(@src(), "Not found '{s}' from={?f}, haystack.cp_count={}", .{ needles_raw, from, haystack.size_cp() });
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

fn FindManyLinear(haystack: String, needles_raw: []const u8, from: ?Index, correct: ?usize) !String.Index {
    var needles = try String.toCodepoints(alloc, needles_raw);
    defer needles.deinit(alloc);
    const start_time = getTime();
    const result = haystack.findManyLinear(needles.items, from, CaseSensitive.Yes) orelse return Error.NotFound;
    const done_in = getTime() - start_time;
    // const print_color = getFgColor(result.gr, correct);
    mtl.debug(@src(), "FoundAt={}/{?}, Time={}{s}", .{ result.gr, correct, done_in, TimeExt });

    return result;
}


fn FindCtring(haystack: Ctring, needles_raw: []const u8, from: ?usize, correct: ?usize) !void {
    const start_time = getTime();
    const v = haystack.view(0, haystack.size());
    const result = v.findUtf8(needles_raw, from);
    const done_in = getTime() - start_time;
    mtl.debug(@src(), "FoundAt={?}/{?}, From={?}, Time={}{s}", .{result, correct, from, done_in, TimeExt });
}

pub fn test_find_index(raw_str: []const u8, needles: []const u8, froms: []const usize, answers: ?[]const usize) !void {
    
    std.debug.print("=" ** 70 ++ "\n", .{});
    const short_string_len: usize = 255;
    var needles_buf = try String.New(needles);
    defer needles_buf.deinit();
    mtl.debug(@src(), "needles_count=\"{s}{}\"", .{ mtl.COLOR_GREEN, needles_buf.size() });
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

    const start_time2 = getTime();
    var ctr_haystack = try Ctring.New(raw_str);
    defer ctr_haystack.deinit();
    const done_in2 = getTime() - start_time2;
    mtl.debug(@src(), "Ctring created in {}{s}", .{done_in2, TimeExt});
    ctr_haystack.printStats(@src());
    const depth: u16 = 32;

    for (0..froms.len) |i| {
        const correct = if (answers) |ans| ans[i] else null;
        const from = froms[i];
        const from_i = haystack.findIndex(from);
        _ = try FindManySimd(haystack, needles, from_i, depth, correct);
        _ = try FindManyLinear(haystack, needles, from_i, correct);
        try FindCtring(ctr_haystack, needles, from, correct);
        
    }
}

test "From File" {
    try String.Init(alloc);
    defer String.Deinit();
    try Ctring.Init(alloc);
    defer Ctring.Deinit();

    const path = try io.getHomeUtf8(alloc, "/Documents/content.xml");
    defer path.deinit();
    var file_contents = try io.readFile(alloc, path);
    defer file_contents.deinit(alloc);
    const needles_raw = "CONCAT(&quot;EC.TYPE=&quot;;[SLAVE1_CAN.G181]))\"";
    
    const from = [_]usize{0};
    const correct = [_]usize{7753055};
    try test_find_index(file_contents.items[0..], needles_raw, from[0..], correct[0..]);
}

test "Speed test 2" {
    if (true) {
        return error.SkipZigTest;
    }
    try String.Init(alloc);
    defer String.Deinit();
    try Ctring.Init(alloc);
    defer Ctring.Deinit();

    const needles = [_]Codepoint{ 's', 'e' };
    const from = [_]usize{ 0, 2, 31 };
    const correct = [_]usize{ 5, 5, 31 };
    try test_find_index(JoseStr, &needles, &from, &correct);
}
