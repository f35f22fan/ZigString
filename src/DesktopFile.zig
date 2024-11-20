pub const DesktopFile = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const alloc = std.testing.allocator;

const zigstr = @import("zigstr");
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

a: Allocator = undefined,
comment: String = undefined,
fullpath: String = undefined,
name: String = undefined,
exec: String = undefined,
generic_name: String = undefined,
icon_path: String = undefined,
ctx: Context = undefined,

pub fn New(altor: Allocator, ctx: Context, fullpath: []const u8) !DesktopFile {
    var df = DesktopFile{};
    df.a = altor;
    df.ctx = ctx;
    df.fullpath = try String.From(altor, ctx, fullpath);
    try df.init();
    return df;
}

pub fn deinit(self: DesktopFile) void {
    self.comment.deinit();
    self.fullpath.deinit();
    self.name.deinit();
    self.exec.deinit();
    self.generic_name.deinit();
    self.icon_path.deinit();
}

pub fn init(self: DesktopFile) !void {
    const path_buf = try self.fullpath.toString();
    defer path_buf.deinit();
    const data_cstr = try io.readFile(self.a, path_buf.items);
    defer self.a.free(data_cstr);
    const data_str = try String.From(self.a, self.ctx, data_cstr);
    defer data_str.deinit();
    var lines = try data_str.split(self.ctx, "\n", CaseSensitive.Yes, KeepEmptyParts.No);
    defer {
        for (lines.items) |line| {
            line.print(std.debug, String.Theme.Dark, "==============Line: ") catch {};
            line.deinit();
        }
        lines.deinit();
    }


}