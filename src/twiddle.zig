const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn someFunc() void {
    var p1 = Person{ .name = "James" };
    p1.talk();

    var home = try io.getEnv(a, io.Folder.home);
    defer a.free(home);
    std.debug.print("home is {s}\n", .{home});
    const input = "Jos\u{65}\u{301}";
    try String.printGraphemes(input);

    const fs = std.fs;
    const flags = fs.File.OpenFlags{ .mode = fs.File.OpenMode.read_write };
    var file = try fs.openFileAbsolute("/home/fox/a.txt", flags);
    defer file.close();
    try file.writeAll("Hello, world from zig\n");
}

pub fn someMem() !void {
    var memory = try a.alloc(u8, 7);
    defer a.free(memory);
    @memset(memory, 0);

    for (0.., memory) |at, *byte| {
        std.debug.print("mem at {} is {}\n", .{ at, byte.* });
    }
}

pub fn printInfoAboutStruct(comptime T: type) void {
    const info = @typeInfo(T);
    inline for (info.Struct.fields) |field| {
        std.debug.print(
            "{s} field \"{s}\":{s}\n",
            .{
                @typeName(T),
                field.name,
                @typeName(field.type),
            },
        );
    }
}

pub const Person = struct {
    name: []const u8,

    pub fn talk(self: *Person) void {
        std.debug.print("hi from person {s}\n", .{self.name});
        self.name = "Michael";
        std.debug.print("hi from person {s}\n", .{self.name});
    }
};
