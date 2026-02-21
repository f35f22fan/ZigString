//MTL is utility code and stands for My Tiny Library
const std = @import("std");
const builtin = @import("builtin");

fn print(out: anytype, comptime fg: []const u8, src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    var wr = out.writer(&buf);
    var writer = &wr.interface;
    writer.print("{s}{s}{s}[{s}]{s}:{d} {s}", .{ fg, src.file, COLOR_CYAN, src.fn_name, fg, src.line, COLOR_DEFAULT }) catch {};
    writer.print(fmt, args) catch {};
    writer.print("{s}\n", .{COLOR_DEFAULT}) catch {};
    writer.flush() catch {};
}

inline fn debug_fg(comptime fg: []const u8, src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    print(std.fs.File.stderr(), fg, src, fmt, args);
}

pub fn info(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    print(std.fs.File.stdout(), COLOR_BLUE, src, fmt, args);
}

pub fn debug(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    debug_fg(COLOR_BLUE, src, fmt, args);
}

pub fn warn(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    debug_fg(COLOR_RED, src, fmt, args);
}

pub fn trace(src: std.builtin.SourceLocation) void {
    line(src, "!");
}

pub fn tbd(src: std.builtin.SourceLocation) void {
    debug_fg(COLOR_MAGENTA, src, "{s}", .{"TBD"});
}

pub fn line(src: std.builtin.SourceLocation, comptime chars: []const u8) void {
    debug(src, chars ** 30, .{});
}

const posix = (builtin.target.os.tag != .windows);

pub const COLOR_BLACK = if (posix) "\x1B[38;5;16m" else "";
pub const COLOR_BLUE = if (posix) "\x1B[34m" else "";
pub const COLOR_CYAN = if (posix) "\x1B[36m" else "";
pub const COLOR_DEFAULT = if (posix) "\x1B[0m" else "";
pub const COLOR_GREEN = if (posix) "\x1B[32m" else "";
pub const COLOR_LIGHTGRAY = if (posix) "\x1B[37m" else "";
pub const COLOR_MAGENTA = if (posix) "\x1B[35m" else "";
pub const COLOR_ORANGE = if (posix) "\x1B[0;33m" else "";
pub const COLOR_RED = if (posix) "\x1B[0;91m" else "";
pub const COLOR_YELLOW = if (posix) "\x1B[93m" else "";
pub const COLOR_OTHER = if (posix) "\x1B[38;5;196m" else "";

pub const BGCOLOR_BLACK = if (posix) "\x1B[40m" else "";
pub const BGCOLOR_BLUE = if (posix) "\x1B[44m" else "";
pub const BGCOLOR_DEFAULT = if (posix) "\x1B[49m" else "";
pub const BGCOLOR_GREEN = if (posix) "\x1B[42m" else "";
pub const BGCOLOR_LIGHTGRAY = if (posix) "\x1B[47m" else "";
pub const BGCOLOR_MAGENTA = if (posix) "\x1B[45m" else "";
pub const BGCOLOR_ORANGE = if (posix) "\x1B[43m" else "";
pub const BGCOLOR_RED = if (posix) "\x1B[41m" else "";
pub const BGCOLOR_YELLOW = if (posix) "\x1B[103m" else "";

pub const BLINK_START = if (posix) "\x1B[5m" else "";
pub const BLINK_END = if (posix) "\x1B[25m" else "";
pub const BOLD_START = if (posix) "\x1B[1m" else "";
pub const BOLD_END = if (posix) "\x1B[0m" else "";
pub const UNDERLINE_START = if (posix) "\x1B[4m" else "";
pub const UNDERLINE_END = if (posix) "\x1B[0m" else "";
