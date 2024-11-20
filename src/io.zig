const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{NotFound};

const Folder = enum(u8) {
    home,
    config,
};

pub fn getEnv(a: Allocator, folder: Folder) ![]const u8 {
    const var_name = switch (folder) {
        Folder.home => "HOME",
        else => return Error.NotFound,
    };

    return std.process.getEnvVarOwned(a, var_name) catch return Error.NotFound;
}

pub fn readFile(alloc: Allocator, full_path: []const u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(full_path, .{});
    defer file.close();
    return file.reader().readAllAlloc(alloc, std.math.maxInt(usize));
}