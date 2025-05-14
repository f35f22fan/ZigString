const std = @import("std");
const Str = @import("String.zig");
const Allocator = std.mem.Allocator;

pub const Error = error{NotFound};

pub const Folder = enum(u8) {
    Home,
    Config,
};

pub fn getEnv(a: Allocator, folder: Folder) ![]const u8 {
    const var_name = switch (folder) {
        Folder.Home => "HOME",
        else => return Error.NotFound,
    };

    return std.process.getEnvVarOwned(a, var_name) catch return Error.NotFound;
}

pub fn getHome(alloc: Allocator, subpath: ?[] const u8) ![]const u8 {
    const home = try getEnv(alloc, Folder.Home);
    if (subpath) |s| {
        defer alloc.free(home);
        var list = std.ArrayList(u8).init(alloc);
        defer list.deinit();
        try list.appendSlice(home);
        try list.appendSlice(s);
        return list.toOwnedSlice();
    } else {
        return home;
    }
}

pub fn readFile(alloc: Allocator, full_path: []const u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(full_path, .{});
    defer file.close();
    return file.reader().readAllAlloc(alloc, std.math.maxInt(usize));
}

pub fn changeExtension(filename: Str, ext: []const u8) !Str {
    const pt_idx = filename.lastIndexOfBytes(".") orelse return Str.Error.Other;
    var out_name = try filename.betweenIndices(.{}, pt_idx);
    try out_name.addBytes(ext);

    return out_name;
}