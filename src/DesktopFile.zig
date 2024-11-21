pub const DesktopFile = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

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

comment: String = undefined,
fullpath: String = undefined,
name: String = undefined,
exec: String = undefined,
generic_name: String = undefined,
icon_path: String = undefined,
dctx: DContext = undefined,

pub const DContext = struct {
    ctx: Context = undefined,
    keyIcon: String = undefined,
    keyExec: String = undefined,
    keyName: String = undefined,
    ownsCtx: u1 = 0,

    pub fn New(ctx: *Context) !DContext {
        var dctx = DContext{};
        dctx.ctx = ctx;
        dctx.keyName = try String.From(ctx, "Name");
        dctx.keyIcon = try String.From(ctx, "Icon");
        dctx.keyExec = try String.From(ctx, "Exec");

        return dctx;
    }

    pub fn NewAlloc(a: Allocator) !DContext {
        var dctx = DContext{};
        dctx.ctx = try Context.New(a);
        dctx.ownsCtx = 1;
        dctx.keyName = try String.From(dctx.ctx, "Name");
        dctx.keyIcon = try String.From(dctx.ctx, "Icon");
        dctx.keyExec = try String.From(dctx.ctx, "Exec");

        return dctx;
    }

    pub fn deinit(self: DContext) void {
        self.keyExec.deinit();
        self.keyIcon.deinit();
        self.keyName.deinit();
        if (self.ownsCtx == 1)
            self.ctx.deinit();
    }
};

pub fn NewCstr(dctx: DContext, fullpath: []const u8) !DesktopFile {
    var df = DesktopFile{};
    df.dctx = dctx;
    df.fullpath = try String.From(dctx.ctx, fullpath);
    try df.init();
    return df;
}

pub fn New(dctx: DContext, fullpath: String) !DesktopFile {
    var df = DesktopFile{};
    df.dctx = dctx;
    df.fullpath = fullpath;
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
    const data_cstr = try io.readFile(self.dctx.ctx.a, path_buf.items);
    defer self.dctx.ctx.a.free(data_cstr);
    const data_str = try String.From(self.dctx.ctx, data_cstr);
    defer data_str.deinit();
    var lines = try data_str.split("\n", CaseSensitive.Yes, KeepEmptyParts.No);
    defer {
        for (lines.items) |line| {
            line.print(std.debug, String.Theme.Dark, "==============Line: ") catch {};
            line.deinit();
        }
        lines.deinit();
    }

    

    for (lines.items) |line| {
        var kv = try line.split("=", CaseSensitive.Yes, KeepEmptyParts.No);
        defer {
            for (kv.items) |s| {
                s.deinit();
            }
            kv.deinit();
        }

        if (kv.items.len != 2)
            continue;
        
        const key = kv.items[0];
        const val = kv.items[1];

        if (key.equalsStr(self.dctx.keyName, CaseSensitive.Yes)) {
            std.debug.print("Found name: {}=\"{}\"\n", .{key, val});
        }
    }
}
