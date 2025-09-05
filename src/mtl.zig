//MTL is utility code and stands for My Tiny Library
const std = @import("std");
const builtin = @import("builtin");

fn print(out: anytype, comptime fg: []const u8, src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    nosuspend out.print("{s}{s}{s}[{s}]{s}:{d} {s}",
    .{fg, src.file, COLOR_CYAN, src.fn_name, fg, src.line, COLOR_DEFAULT}) catch {};
    nosuspend out.print(fmt, args) catch {};
    nosuspend out.print("{s}\n", .{COLOR_DEFAULT}) catch {};
}

inline fn msg(comptime fg: []const u8, src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    print(std.io.getStdOut().writer(), fg, src, fmt, args);
}

inline fn debugger(comptime fg: []const u8, src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    print(std.io.getStdErr().writer(), fg, src, fmt, args);
}

pub inline fn info(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    msg(COLOR_BLUE, src, fmt, args);
}

pub inline fn debug(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    debugger(COLOR_BLUE, src, fmt, args);
}

pub inline fn warn(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    debugger(COLOR_RED, src, fmt, args);
}

pub inline fn trace(src: std.builtin.SourceLocation) void {
    debug(src, "{{trace}}", .{});
}

pub inline fn tbd(src: std.builtin.SourceLocation) void {
    debugger(COLOR_MAGENTA, src, "{s}", .{"TBD"});
}

pub fn separator(src: std.builtin.SourceLocation, comptime chars: []const u8) void {
    debug(src, chars ** 30, .{});
}


const posix = (builtin.target.os.tag == .linux);
pub const COLOR_BLUE = if (posix) "\x1B[34m" else "";
pub const COLOR_DEFAULT = if (posix) "\x1B[0m" else "";
pub const COLOR_GREEN = if (posix) "\x1B[32m" else "";
pub const COLOR_RED = if (posix) "\x1B[0;91m" else "";
pub const COLOR_YELLOW = if (posix) "\x1B[93m" else "";
pub const COLOR_MAGENTA = if (posix) "\x1B[35m" else "";
pub const COLOR_CYAN = if (posix) "\x1B[36m" else "";
pub const COLOR_BLACK = if (posix) "\x1B[38;5;16m" else "";
pub const BLINK_START = if (posix) "\x1B[5m" else "";
pub const BLINK_END = if (posix) "\x1B[25m" else "";
pub const BOLD_START = if (posix) "\x1B[1m" else "";
pub const BOLD_END = if (posix) "\x1B[0m" else "";
pub const UNDERLINE_START = if (posix) "\x1B[4m" else "";
pub const UNDERLINE_END = if (posix) "\x1B[0m" else "";
