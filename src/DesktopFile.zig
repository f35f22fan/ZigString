pub const DesktopFile = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const KVHash = std.StringHashMap(String);
const GroupHash = std.StringHashMap(KVHash);

const zigstr = @import("zigstr");
const io = @import("io.zig");

const Normalize = @import("Normalize");
const CaseFold = @import("CaseFold");
const ScriptsData = @import("ScriptsData");

const String = @import("String.zig").String;
const CaseSensitive = String.CaseSensitive;
const Codepoint = String.Codepoint;
const CodepointSlice = String.CpSlice;
const Context = String.Context;
const CpSlice = String.CpSlice;
const Error = String.Error;
const Index = String.Index;
const KeepEmptyParts = String.KeepEmptyParts;

groups: GroupHash = undefined,
comment: ?String = null,
fullpath: ?String = null,
name: ?String = null,
exec: ?String = null,
icon: ?String = null,
alloc: Allocator = undefined,

const CstrName = "Name";
const CstrExec = "Exec";
const CstrIcon = "Icon";
const CstrGenericName = "GenericName";

pub fn NewCstr(a: Allocator, fullpath: []const u8) !DesktopFile {
    return New(a, try String.From(fullpath));
}

pub fn New(a: Allocator, fullpath: String) !DesktopFile {
    var df = DesktopFile{
        .alloc = a,
        .groups = GroupHash.init(a),
    };
    df.fullpath = fullpath;
    try df.init();

    return df;
}

pub fn deinit(self: *DesktopFile) void {

    var groups_iter = self.groups.iterator();
    while (groups_iter.next()) |group_kv|
    {
        const name = group_kv.key_ptr;
        self.alloc.free(name.*);
        var value = group_kv.value_ptr;
        var iter = value.iterator();
        while (iter.next()) |kv| {
            self.alloc.free(kv.key_ptr.*);
            kv.value_ptr.deinit();
        }
        value.deinit();
    }

    self.groups.deinit();
    
    if (self.fullpath) |k| {
        k.deinit();
    }
}

fn put(a: Allocator, key: String, value: String, dest: *KVHash) !void {
    std.debug.print("{s}(): key=\"{s}\", value=\"{}\"\n", .{ @src().fn_name, key, value });
    if (key.isEmpty()) {
        const cstr_key = try a.dupe(u8, "");
        
        try dest.put(cstr_key, value);
    } else {
        const cstr_key = try key.dup_as_cstr_alloc(a);
        try dest.put(cstr_key, value);
    }
}

fn splitKey(key: String) !?struct { String, String } {
    const index = key.indexOfCp("[", Index.strStart(), CaseSensitive.Yes) orelse return null;
    return .{ try key.between(0, index.gr), try key.between(index.gr + 1, key.size() - 1) };
}

pub fn init(self: *DesktopFile) !void {
    const fp = self.fullpath orelse return String.Error.NotFound;
    const path_buf = try fp.toString();
    defer path_buf.deinit();
    const data_cstr = try io.readFile(self.alloc, path_buf.items);

    const data_str = try String.From(data_cstr);
    self.alloc.free(data_cstr);
    defer data_str.deinit();
    var lines = try data_str.split("\n", CaseSensitive.Yes, KeepEmptyParts.No);
    defer {
        for (lines.items) |line| {
            line.deinit();
        }
        lines.deinit();
    }

    var current_hash_opt: ?*KVHash = null;

    for (lines.items) |line| {
        if (line.startsWithChar("#")) {
            try line.print(std.debug, "Comment: ");
            continue;
        }
        if (line.isBetween("[", "]")) |group_name| {
            defer group_name.deinit();
            const name_cstr = try group_name.dupAsCstr();
            const h = KVHash.init(self.alloc);
            try self.groups.put(name_cstr, h);
            current_hash_opt = self.groups.getPtr(name_cstr) orelse break;
            continue;
        }
        //try line.print(std.debug, "Line: ");
        var current_hash: *KVHash = current_hash_opt orelse break;
        var kv = try line.split("=", CaseSensitive.Yes, KeepEmptyParts.Yes);
        defer {
            for (kv.items) |s| {
                s.deinit();
            }
            kv.deinit();
        }

        const key = try kv.items[0].Clone();
        defer key.deinit();
        const value = if (kv.items.len == 2) try kv.items[1].Clone() else String.New();
        const final_key = try key.dupAsCstrAlloc(self.alloc);
        std.debug.print("\"{s}\"=>\"{s}{}{s}\"\n",
        .{final_key, String.COLOR_BLUE, value, String.COLOR_DEFAULT});
        try current_hash.put(final_key, value);
    }
}
