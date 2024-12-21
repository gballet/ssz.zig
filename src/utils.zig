const std = @import("std");
const lib = @import("./lib.zig");
const serialize = lib.serialize;
const deserialize = lib.deserialize;
const isFixedSizeObject = lib.isFixedSizeObject;
const ArrayList = std.ArrayList;

/// Implements the SSZ `List[N]` container.
pub fn List(comptime T: type, comptime N: usize) type {
    return struct {
        const Self = @This();
        const Item = T;
        const Inner = @TypeOf(Self.inner);

        inner: std.BoundedArray(T, N),

        pub fn sszEncode(self: *const Self, l: *ArrayList(u8)) !void {
            try serialize([]const Item, self.inner.slice(), l);
        }

        pub fn sszDecode(serialized: []const u8, out: *Self) !void {
            // BitList[N] or regular List[N]?
            if (Self.Item == bool) {
                for (serialized, 0..) |byte, bindex| {
                    var i = @as(u8, 0);
                    var b = byte;
                    while (bindex * 8 + i < out.len and i < 8) : (i += 1) {
                        out[bindex * 8 + i] = b & 1 == 1;
                        b >>= 1;
                    }
                }
            } else if (try isFixedSizeObject(Self.Item)) {
                var i: usize = 0;
                const pitch = @sizeOf(Self.Item);
                while (i < serialized.len) : (i += pitch) {
                    var item: Self.Item = undefined;
                    try deserialize(Self.Item, serialized[i .. i + pitch], &item);
                    try out.append(item);
                }
            } else {
                // first variable index is also the size of the list
                // of indices. Recast that list as a []const u32.
                const size = std.mem.readInt(u32, serialized[0..4], std.builtin.Endian.little) / @sizeOf(u32);
                const indices = std.mem.bytesAsSlice(u32, serialized[0 .. size * 4]);
                var i = @as(usize, 0);
                while (i < size) : (i += 1) {
                    const end = if (i < size - 1) indices[i + 1] else serialized.len;
                    const start = indices[i];
                    if (start >= serialized.len or end > serialized.len) {
                        return error.IndexOutOfBounds;
                    }
                    const item = try out.inner.addOne();
                    try deserialize(Self.Item, serialized[start..end], item);
                }
            }
        }

        pub fn init(len: usize) error{Overflow}!Self {
            return .{ .inner = try std.BoundedArray(T, N).init(len) };
        }

        pub fn eql(self: *const Self, other: *Self) bool {
            return (self.inner.len == other.inner.len) and std.mem.eql(Self.Item, self.inner.constSlice()[0..self.inner.len], other.inner.constSlice()[0..other.inner.len]);
        }

        pub fn append(self: *Self, item: Self.Item) error{Overflow}!void {
            return self.inner.append(item);
        }

        pub fn slice(self: *Self) []T {
            return self.inner.slice();
        }

        pub fn fromSlice(m: []const T) error{Overflow}!Self {
            return .{ .inner = try Inner.fromSlice(m) };
        }

        pub fn get(self: Self, i: usize) T {
            return self.inner.get(i);
        }

        pub fn set(self: *Self, i: usize, item: T) void {
            self.inner.set(i, item);
        }
    };
}
