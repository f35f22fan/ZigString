pub const DesktopFile = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const StringHashMap = std.StringHashMap;

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

comment: ?String = null,
fullpath: ?String = null,
name: ?String = null,
exec: ?String = null,
generic_names: StringHashMap(String) = undefined,
icon: ?String = null,
dctx: DContext = undefined,

const CstrName = "Name";
const CstrExec = "Exec";
const CstrIcon = "Icon";
const CstrGenericName = "GenericName";

pub const DContext = struct {
    altor: Allocator = undefined,
    keyIcon: String = undefined,
    keyExec: String = undefined,
    keyName: String = undefined,
    keyGenericName: String = undefined,

    pub fn New(a: Allocator) !DContext {
        var dctx = DContext{};
        dctx.altor = a;
        try dctx.init();
        return dctx;
    }

    fn init(self: *DContext) !void {
        self.keyName = try String.From(CstrName);
        self.keyIcon = try String.From(CstrIcon);
        self.keyExec = try String.From(CstrExec);
        self.keyGenericName = try String.From(CstrGenericName);
    }

    pub fn deinit(self: DContext) void {
        self.keyExec.deinit();
        self.keyIcon.deinit();
        self.keyName.deinit();
        self.keyGenericName.deinit();
    }
};

pub fn NewCstr(dctx: DContext, fullpath: []const u8) !DesktopFile {
    return New(dctx, try String.From(fullpath));
}

pub fn New(dctx: DContext, fullpath: String) !DesktopFile {
    var df = DesktopFile{
        .generic_names = std.StringHashMap(String).init(dctx.altor),
    };
    df.dctx = dctx;
    df.fullpath = fullpath;
    try df.init();

    return df;
}

pub fn deinit(self: *DesktopFile) void {
    if (self.comment)|k|
        k.deinit();
    if (self.fullpath)|k|
        k.deinit();
    if (self.name)|k|
        k.deinit();
    if (self.exec)|k|
        k.deinit();
    if (self.icon)|k|
        k.deinit();
    self.generic_names.deinit();
}

fn splitKey(key: String) !?struct{String, String} {
    const index = key.indexOfCp("[", Index.strStart(), CaseSensitive.Yes) orelse return null;
    return .{ try key.between(0, index.gr), try key.between(index.gr+1, key.size()-2) };
}

pub fn init(self: *DesktopFile) !void {
    const fp = self.fullpath orelse return String.Error.NotFound;
    const path_buf = try fp.toString();
    defer path_buf.deinit();
    const data_cstr = try io.readFile(self.dctx.altor, path_buf.items);
    
    const data_str = try String.From(data_cstr);
    self.dctx.altor.free(data_cstr);
    defer data_str.deinit();
    var lines = try data_str.split("\n", CaseSensitive.Yes, KeepEmptyParts.No);
    defer {
        for (lines.items) |line| {
            //line.print(std.debug, null) catch {};
            line.deinit();
        }
        lines.deinit();
    }
    //std.debug.print("{s}:{}(), lines: {}\n", .{@src().fn_name, @src().line, lines.items.len});
    for (lines.items) |line| {
        if (line.startsWithChar("#")) {
            try line.print(std.debug, "Comment: ");
            continue;
        }
        if (line.startsWithChar("[")) {
            if (line.endsWithChar("]")) {
                const name = try line.between(1, line.size() - 2);
                //try name.print(std.debug, "New group: ");
                defer name.deinit();
                continue;
            } else {
                std.debug.print("{s}: Line doesn't end with ]\n", .{@src().fn_name});
                continue;
            }
        }
        var kv = try line.split("=", CaseSensitive.Yes, KeepEmptyParts.Yes);
        defer {
            for (kv.items) |s| {
                s.deinit();
            }
            kv.deinit();
        }
        
        //var key = kv.items[0];
        var key = try kv.items[0].Clone();
        var lang: String = undefined;
        var found = false;
        if (key.endsWithChar("]")) {
            if (try splitKey(key)) |pair| {
            //  if (both) |pair| {
                found = true;
                key.deinit();
                key = pair[0];
                lang = pair[1];
            }
        }

        if (found)
            lang.deinit();
        defer key.deinit();
        const value = if (kv.items.len == 2) try kv.items[1].Clone() else String.New();
        std.debug.print("key=\"{}\" => \"{}\", count: {}\n", .{key, value, kv.items.len});
        if (key.eqStr(self.dctx.keyName)) {
            try value.print(std.debug, "Found name: ");
            if (self.name)|k|
                k.deinit();
            self.name = value;
        } else if (key.eqStr(self.dctx.keyExec)) {
            try value.print(std.debug, "Found exec: ");
            if (self.exec)|k|
                k.deinit();
            self.exec = value;
        } else if (key.eqStr(self.dctx.keyIcon)) {
            try value.print(std.debug, "Found icon: ");
            if (self.icon)|k|
                k.deinit();
            self.icon = value;
        // } else if (key.eqStr(self.dctx.keyGenericName)) {
        //     try value.print(std.debug, "Found generic name: ");
        //     if (self.generic_name)|k|
        //         k.deinit();     
        //     self.generic_name = value;
        } else {
            value.deinit();
        }
    }
}
