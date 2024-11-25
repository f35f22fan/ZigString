const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const alloc = std.testing.allocator;

const io = @import("io.zig");

const Normalize = @import("Normalize");
const CaseFold = @import("CaseFold");
const ScriptsData = @import("ScriptsData");

const String = @import("String.zig").String;
const CaseSensitive = String.CaseSensitive;
const Codepoint = String.Codepoint;
const CodepointSlice = String.CodepointSlice;
const Context = String.Context;
const CpSlice = String.CpSlice;
const Error = String.Error;
const Index = String.Index;
const KeepEmptyParts = String.KeepEmptyParts;

const DesktopFile = @import("DesktopFile.zig").DesktopFile;
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

fn ticker(step: u8) !void {
    _ = step;
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();   
    var s = try String.From("Hello, World!");
    try s.append("...From another thread");
    defer s.deinit();
    std.debug.print("{s}():==================== {}\n", .{@src().fn_name, s});
    // while (true) {
    //     std.time.sleep(1 * std.time.ns_per_s);
    //     tick += @as(isize, step);
    // }
}

var tick: isize = 0;


test "Desktop File" {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    // const thread = try std.Thread.spawn(.{}, ticker, .{@as(u8, 1)});
    // thread.join();

    // if (true)
    //     return;

    var dctx = try DesktopFile.DContext.New(alloc);
    defer dctx.deinit();

    const home_cstr = try io.getEnv(alloc, io.Folder.Home);
    defer alloc.free(home_cstr);
    
    var fullpath = try String.From(home_cstr);
    defer fullpath.deinit();
    try fullpath.append("/Desktop/Firefox.desktop");
    try fullpath.print(std.debug, "Fullpath: ");
    var df = try DesktopFile.New(dctx, try fullpath.Clone());
    defer df.deinit();
}