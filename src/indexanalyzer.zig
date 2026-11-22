//! Vertex cache and vertex fetch analysis: how an index buffer would use a
//! GPU's post-transform cache and its vertex memory, in simple models of
//! both.
//!
//! Translated from meshoptimizer's indexanalyzer.cpp.

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Scratch = @import("allocator.zig").Scratch;
const checkIndex = @import("index.zig").check;

pub const VertexCacheStatistics = struct {
    vertices_transformed: u32 = 0,
    warps_executed: u32 = 0,
    /// Transformed vertices per triangle: 0.5 at best, 3 at worst; the
    /// best reachable depends on the topology.
    acmr: f32 = 0,
    /// Transformed vertices per vertex: 1 at best, each vertex transformed
    /// once, and 6 at worst.
    atvr: f32 = 0,
};

/// Counts the vertex shader runs `indices` costs on a GPU with a FIFO
/// post-transform cache of `cache_size` vertices (at least 3), warps of
/// `warp_size` vertices (0 for no warps, else at least 3), and primitive
/// groups of `primgroup_size` triangles (0 for none). The model is simple,
/// and real GPUs may differ.
pub fn analyzeVertexCache(
    comptime Index: type,
    gpa: Allocator,
    indices: []const Index,
    vertex_count: usize,
    cache_size: u32,
    warp_size: u32,
    primgroup_size: u32,
) Allocator.Error!VertexCacheStatistics {
    comptime checkIndex(Index);
    assert(indices.len % 3 == 0);
    assert(cache_size >= 3);
    assert(warp_size == 0 or warp_size >= 3);

    var scratch: Scratch = .init(gpa);
    defer scratch.deinit();

    var result: VertexCacheStatistics = .{};

    var warp_offset: u32 = 0;
    var primgroup_offset: u32 = 0;

    const cache_timestamps = try scratch.alloc(u32, vertex_count);
    @memset(cache_timestamps, 0);

    // The original's unsigned arithmetic wraps, and so does the port's.
    var timestamp: u32 = cache_size +% 1;

    var i: usize = 0;
    while (i < indices.len) : (i += 3) {
        const a = indices[i + 0];
        const b = indices[i + 1];
        const c = indices[i + 2];
        assert(a < vertex_count and b < vertex_count and c < vertex_count);

        const ac: u32 = @intFromBool(timestamp -% cache_timestamps[a] > cache_size);
        const bc: u32 = @intFromBool(timestamp -% cache_timestamps[b] > cache_size);
        const cc: u32 = @intFromBool(timestamp -% cache_timestamps[c] > cache_size);

        // Flush the cache when the triangle fits neither the warp nor the
        // primitive buffer.
        if ((primgroup_size != 0 and primgroup_offset == primgroup_size) or
            (warp_size != 0 and warp_offset +% ac +% bc +% cc > warp_size))
        {
            result.warps_executed +%= @intFromBool(warp_offset > 0);

            warp_offset = 0;
            primgroup_offset = 0;

            // Every vertex in the cache now counts as out of it.
            timestamp +%= cache_size +% 1;
        }

        // Update the cache and add the vertices to the warp.
        for (indices[i..][0..3]) |index| {
            if (timestamp -% cache_timestamps[index] > cache_size) {
                cache_timestamps[index] = timestamp;
                timestamp +%= 1;
                result.vertices_transformed +%= 1;
                warp_offset +%= 1;
            }
        }

        primgroup_offset +%= 1;
    }

    var unique_vertex_count: usize = 0;

    for (cache_timestamps) |t| unique_vertex_count += @intFromBool(t > 0);

    result.warps_executed +%= @intFromBool(warp_offset > 0);

    const transformed: f32 = @floatFromInt(result.vertices_transformed);
    result.acmr = if (indices.len == 0)
        0
    else
        transformed / @as(f32, @floatFromInt(indices.len / 3));
    result.atvr = if (unique_vertex_count == 0)
        0
    else
        transformed / @as(f32, @floatFromInt(unique_vertex_count));

    return result;
}

pub const VertexFetchStatistics = struct {
    bytes_fetched: u32 = 0,
    /// Fetched bytes per byte of the vertices used: 1 at best, each byte
    /// fetched once.
    overfetch: f32 = 0,
};

/// Counts the bytes of vertex memory `indices` costs to fetch, in
/// 64-byte lines through a 128 KiB direct-mapped cache, for vertices of
/// `vertex_size` bytes. The model is simple, and real GPUs may differ.
pub fn analyzeVertexFetch(
    comptime Index: type,
    gpa: Allocator,
    indices: []const Index,
    vertex_count: usize,
    vertex_size: usize,
) Allocator.Error!VertexFetchStatistics {
    comptime checkIndex(Index);
    assert(vertex_size > 0 and vertex_size <= 256);

    var scratch: Scratch = .init(gpa);
    defer scratch.deinit();

    var result: VertexFetchStatistics = .{};

    const vertex_visited = try scratch.alloc(u8, vertex_count);
    @memset(vertex_visited, 0);

    const cache_line = 64;
    const cache_size = 128 * 1024;

    // On typical meshes a direct-mapped cache comes close to a 4-way one,
    // and the model is a rough approximation anyway.
    var cache: [cache_size / cache_line]usize = @splat(0);

    for (indices) |index| {
        assert(index < vertex_count);

        vertex_visited[index] = 1;

        const start_address = index * vertex_size;
        const end_address = start_address + vertex_size;

        const start_tag = start_address / cache_line;
        const end_tag = (end_address + cache_line - 1) / cache_line;

        for (start_tag..end_tag) |tag| {
            const line = tag % cache.len;

            // Lines hold their tag plus one, as the cache starts zeroed.
            // Without a branch, as the original adds the comparison times
            // the line size: a miss is too unpredictable to branch on.
            result.bytes_fetched +%= @as(u32, @intFromBool(cache[line] != tag + 1)) * cache_line;
            cache[line] = tag + 1;
        }
    }

    const unique_vertex_count = countVisited(vertex_visited);

    result.overfetch = if (unique_vertex_count == 0)
        0
    else
        @as(f32, @floatFromInt(result.bytes_fetched)) /
            @as(f32, @floatFromInt(unique_vertex_count * vertex_size));

    return result;
}

/// The sum of `visited`, whose bytes are 0 or 1, on vectors: the original's
/// compiler vectorizes its loop, and Zig's does not.
fn countVisited(visited: []const u8) usize {
    const lanes = 64;
    const V = @Vector(lanes, u8);
    var total: usize = 0;
    var i: usize = 0;

    // A byte lane holds at most 255 ones, so the lanes are summed into the
    // total every 255 vectors.
    while (visited.len - i >= lanes) {
        const vectors: usize = @min((visited.len - i) / lanes, 255);
        const chunk_end = i + vectors * lanes;
        var acc: V = @splat(0);
        while (i < chunk_end) : (i += lanes) acc += visited[i..][0..lanes].*;
        total += @reduce(.Add, @as(@Vector(lanes, u16), acc));
    }

    for (visited[i..]) |v| total += v;
    return total;
}

// --------------------------------------------------------
// Tests
// --------------------------------------------------------

const testing = std.testing;

test "a cached vertex costs nothing again" {
    // Two triangles sharing an edge: 4 vertices for 2 triangles.
    const indices = [_]u32{ 0, 1, 2, 2, 1, 3 };
    const stats = try analyzeVertexCache(u32, testing.allocator, &indices, 4, 16, 0, 0);
    try testing.expectEqual(4, stats.vertices_transformed);
    try testing.expectEqual(2.0, stats.acmr);
    try testing.expectEqual(1.0, stats.atvr);
}

test "the visited count on vectors matches a plain sum" {
    // Past 255 vectors, so the byte lanes are flushed more than once, and a
    // tail that is not a whole vector.
    var prng: std.Random.DefaultPrng = .init(1);
    const random = prng.random();
    for ([_]usize{ 0, 1, 63, 64, 65, 255 * 64, 255 * 64 + 1, 100_003 }) |len| {
        const visited = try testing.allocator.alloc(u8, len);
        defer testing.allocator.free(visited);
        var expected: usize = 0;
        for (visited) |*v| {
            v.* = @intFromBool(random.boolean());
            expected += v.*;
        }
        try testing.expectEqual(expected, countVisited(visited));
        @memset(visited, 1);
        try testing.expectEqual(len, countVisited(visited));
    }
}
