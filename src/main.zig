const std = @import("std");

const Card = @import("Card.zig");
const c = @import("c.zig");

pub fn main() !void {
    try actualMain();
    //actualMain() catch |err| {
    //    std.log.crit("poop: {}", .{err});
    //};
    //while (true) {
    //    asm volatile ("" ::: "memory");
    //}
}

fn actualMain() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var card = try Card.open("/dev/dri/card0");
    defer card.close();

    const Framebuffer = struct {
        base: []align(@alignOf(u32)) u8,
        width: usize,
        height: usize,
        crtc: Card.drm_mode_crtc,
    };

    var framebuffers: [10]?Framebuffer = undefined;

    {
        try card.getMaster();
        defer card.dropMaster() catch |e| std.debug.panic("{}", .{e});

        var resource_handles = try card.getResourceHandles(arena.allocator());
        defer resource_handles.deinit();

        std.log.info("fb: {}, crtc: {}, conn: {}, enc: {}", .{
            resource_handles.fbs.len,
            resource_handles.crtcs.len,
            resource_handles.connectors.len,
            resource_handles.encoders.len,
        });

        //Loop though all available connectors
        for (resource_handles.connectors) |connector_id, connector_index| {
            var connector = try card.getConnector(allocator, connector_id);
            defer connector.deinit();

            std.log.info("connector[{}]:", .{connector_index});
            std.log.info("\tdimension       = {}", .{connector.physical_dimension});
            std.log.info("\tcurrent encoder = {}", .{connector.current_encoder});
            std.log.info("\tconnection      = {}", .{connector.connection});

            for (connector.modes) |mode, i| {
                std.log.info("\tmode[{}]        = {}×{}\t{}Hz,\t\"{s}\"", .{ i, mode.hdisplay, mode.vdisplay, mode.vrefresh, std.mem.sliceTo(@ptrCast(*const [32:0]u8, &mode.name), 0) });
            }

            for (connector.available_encoders) |encoder, i| {
                std.log.info("\tencoder[{}]     = {}", .{ i, encoder });
            }

            //Check if the connector is OK to use (connected to something)
            if (connector.available_encoders.len < 1 or connector.modes.len < 1 or connector.current_encoder == null or connector.connection != .connected) {
                std.log.info("connector[{}]: Not connected", .{connector_index});
                continue;
            } else {
                std.log.info("connector[{}]: connected, {}×{}", .{
                    connector_index,
                    connector.modes[0].hdisplay,
                    connector.modes[0].vdisplay,
                });
            }

            var buffer = try card.createDumbBuffer(
                connector.modes[0].hdisplay,
                connector.modes[0].vdisplay,
                32,
            );
            errdefer buffer.deinit();

            var map_offset = try buffer.map();

            var fb_id = try buffer.addFB(24); // 24 bit color depth

            var enc = try card.getEncoder(connector.current_encoder.?);

            var fb = Framebuffer{
                .base = try std.os.mmap(
                    null,
                    buffer.size,
                    std.os.linux.PROT.READ | std.os.linux.PROT.WRITE,
                    std.os.linux.MAP.SHARED,
                    card.file.handle,
                    map_offset,
                ),
                .width = buffer.width,
                .height = buffer.height,
                .crtc = try card.getCrtc(enc.crtc_id),
            };

            // //------------------------------------------------------------------------------
            // //Kernel Mode Setting (KMS)
            // //------------------------------------------------------------------------------

            // std.log.info("{}: {} : mode: {}, prop: {}, enc: {}", .{ i, conn.connection, conn.count_modes, conn.count_props, conn.count_encoders });
            // std.log.info("{}: modes: {}x{} FB: {*}", .{ i, conn_mode_buf[0].hdisplay, conn_mode_buf[0].vdisplay, framebuffers[i].base });

            var crtc = fb.crtc;

            std.log.info("crtc = {}", .{crtc});

            crtc.fb_id = fb_id;
            crtc.set_connectors_ptr = @ptrToInt(&connector_id);
            crtc.count_connectors = 1;
            crtc.mode = connector.modes[0];
            crtc.mode_valid = 1;

            try card.setCrtc(crtc);

            framebuffers[connector_index] = fb;
        }
    }

    for (framebuffers) |fb_or_null, i| {
        if (fb_or_null) |fb| {
            std.log.info("fb[{}] = {}×{}, {*}", .{ i, fb.width, fb.height, fb.base.ptr });
        } else {
            std.log.info("fb[{}] = N.A.", .{i});
        }
    }

    {
        //var random = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp()));

        var i: usize = 0;
        while (i < 30) : (i += 1) {
            for (framebuffers) |fb_or_null| {
                const fb = fb_or_null orelse continue;

                const base_col: u32 = @truncate(u8, i);

                var y: usize = 0;
                while (y < fb.height) : (y += 1) {
                    var x: usize = 0;
                    while (x < fb.width) : (x += 1) {
                        const col = base_col ^
                            @truncate(u32, (x & 0xFF) << 0) ^
                            @truncate(u32, (y & 0xFF) << 0);

                        const location = y * (@intCast(usize, fb.width)) + x;

                        const ptr = @ptrCast([*]u32, fb.base.ptr) + location;
                        ptr.* = col;
                    }
                }
            }
            std.time.sleep(100 * std.time.ns_per_ms);
        }
    }
}
