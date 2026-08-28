const std = @import("std");
const Str = @import("String.zig");
const Ctring = @import("Ctring.zig");
const mtl = @import("mtl.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const Error = error{NotFound};

pub const Folder = enum(u8) {
    Home,
    Config,
};

pub const Truncate = enum(u8) {
    Yes,
    No,
};

const FileEntry = struct {
    kind: std.fs.File.Kind,
    name: []const u8,

    pub fn From(alloc: Allocator, entry: std.Io.Dir.Entry) !FileEntry {
        return .{ .kind = entry.kind, .name = try alloc.dupe(u8, entry.name) };
    }

    pub fn deinit(self: FileEntry, alloc: Allocator) void {
        alloc.free(self.name);
    }
};

pub fn getEnv(gpa: Allocator, env: std.process.Environ, folder: Folder) ![]const u8 {
    const var_name = switch (folder) {
        Folder.Home => "HOME",
        else => return Error.NotFound,
    };

    const value = try env.getAlloc(gpa, var_name);
    // const value = try std.testing.environ.getAlloc(a, var_name);
    // mtl.debug(@src(), "Value: {s}", .{value});

    return value;
}

pub fn getHome2(gpa: Allocator, env: std.process.Environ, subpath: ?Ctring) !Ctring {
    const home = try getEnv(gpa, env, Folder.Home);
    defer gpa.free(home);
    if (subpath) |s| {
        var ret = try Ctring.New(home);
        // mtl.debug(@src(), "inital ret:{f}", .{ret._(2)});
        try ret.add(s);
        // mtl.debug(@src(), "home:{s}, ret:{f}, subpath:{f}", .{home, ret._(2), s._(2)});
        return ret;
    } else {
        return Ctring.New(home);
    }
}

pub fn getHome(gpa: Allocator, env: std.process.Environ, subpath: ?Str) !Str {
    const home = try getEnv(gpa, env, Folder.Home);
    defer gpa.free(home);
    if (subpath) |s| {
        var ret = try Str.NewAscii(home);
        try ret.add(s);
        return ret;
    } else {
        return Str.New(home);
    }
}

pub fn listFiles(gpa: Allocator, folder: ?Folder, subdir: ?Str) !std.ArrayList(FileEntry) {
    var dir: std.Io.Dir = undefined;

    var fullpath: Str = Str.New();
    defer fullpath.deinit();

    if (folder) |f| {
        fullpath = switch (f) {
            .Home => try getHome(gpa, null),
            .Config => return error.BadArg, // to be implemented!
        };

        if (subdir) |subpath| {
            if (!subpath.startsWithCp('/') and !fullpath.endsWithCp('/')) {
                try fullpath.addAscii("/");
            }

            try fullpath.add(subpath);
        }
    } else {
        const utf8 = subdir orelse return error.BadArg;
        fullpath = try utf8.Clone();
    }

    mtl.debug(@src(), "{dt}", .{fullpath});
    const bytes = try fullpath.toUtf8();
    defer bytes.deinit();
    dir = try openDirUtf8(bytes.items);
    defer dir.close();
    var iter = dir.iterate();
    var list = std.ArrayList(FileEntry).init(gpa);
    errdefer {
        for (list.items) |item| {
            item.deinit(gpa);
        }
        list.deinit();
    }

    while (try iter.next()) |entry| {
        try list.append(try FileEntry.From(gpa, entry));
        // mtl.debug(@src(), "\"{s}\", kind={}", .{entry.name, entry.kind});
    }

    return list;
}

pub fn listFilesUtf8(gpa: Allocator, folder: ?Folder, subdir: ?[]const u8) !std.ArrayList(FileEntry) {
    var subpath: ?Str = null;
    defer {
        if (subpath) |sp| {
            sp.deinit();
        }
    }
    if (subdir) |sd| {
        subpath = try Str.From(sd);
    }
    return listFiles(gpa, folder, subpath);
}

pub fn openDir(gpa: Allocator, io: std.Io, fullpath: Str) !std.Io.Dir {
    var bytes = try fullpath.toUtf8(gpa);
    defer bytes.deinit(gpa);
    return openDirUtf8(io, bytes.items);
}

pub fn openDir2(gpa: Allocator, io: std.Io, fullpath: Ctring) !std.Io.Dir {
    var bytes = try fullpath.toBytes(gpa, .{});
    defer bytes.deinit(gpa);
    return openDirUtf8(io, bytes.items);
}

pub fn openDirUtf8(io: std.Io, fullpath: []const u8) !std.Io.Dir {
    const dir = try std.Io.Dir.openDirAbsolute(io, fullpath, .{ .iterate = true, .follow_symlinks = false });
    return dir;
}

pub fn readFile(gpa: Allocator, io: std.Io, full_path: Str) !ArrayList(u8) {
    var bytes = try full_path.toUtf8(gpa);
    defer bytes.deinit(gpa);
    return readFileUtf8(gpa, io, bytes.items);
}

pub fn readFile2(gpa: Allocator, io: std.Io, full_path: Ctring) !ArrayList(u8) {
    var bytes = try full_path.toBytes(gpa, .{});
    defer bytes.deinit(gpa);
    return readFileUtf8(gpa, io, bytes.items);
}

pub fn readFileUtf8(gpa: Allocator, io: std.Io, full_path: []const u8) !ArrayList(u8) {
    const file = try std.Io.Dir.openFileAbsolute(io, full_path, .{});
    defer file.close(io);
    // return file.reader().readAllAlloc(alloc, std.math.maxInt(usize));
    var buf_in: [4096]u8 = undefined;
    var dest_buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &buf_in);
    var iface = &file_reader.interface;
    var arr: ArrayList(u8) = .empty;

    while (true) {
        const num = try iface.readSliceShort(&dest_buf);
        if (num == 0) {
            break;
        }
        try arr.appendSlice(gpa, dest_buf[0..num]);
    }

    return arr;
}

pub fn toNewFile(io: std.Io, path: []const u8, data: []const u8, truncate: Truncate) !void {
    const out_file = try std.Io.Dir.openFileAbsolute(io, path, .{.mode = .write_only,});
    defer out_file.close(io);

    try writeAll(io, out_file, data, truncate);
}

pub fn writeAll(io: std.Io, out: std.Io.File, data: []const u8, truncate: Truncate) !void {
    var file_buf: [4096]u8 = undefined;
    var writer = out.writer(io, &file_buf);
    if (truncate == .No) { // workaround for https://github.com/ziglang/zig/issues/14375
        // The downside is that this is not atomic.
        const stat = try out.stat(io);
        try writer.seekTo(stat.size);
    }
    
    var at: usize = 0;
    while (true) {
        const num = try writer.interface.write(data[at..]);
        if (num == 0) {
            mtl.debug(@src(), "Reached the end", .{});
            break;
        }
        mtl.debug(@src(), "Wrote {} bytes", .{num});
        at += num;
    }

    try writer.interface.flush();
}
