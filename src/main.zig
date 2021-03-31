const std = @import("std");

const Card = @import("Card.zig");
const c = @import("c.zig");

const ioctl = std.os.linux.ioctl;

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

    const allocator = &gpa.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var card = try Card.open("/dev/dri/card0");
    defer card.close();

    const Framebuffer = struct {
        base: []align(@alignOf(u32)) u8,
        width: usize,
        height: usize,
    };

    var framebuffers: [10]?Framebuffer = undefined;

    {
        try card.getMaster();
        defer card.dropMaster() catch |e| std.debug.panic("{}", .{e});

        var resource_handles = try card.getResourceHandles(&arena.allocator);
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
                std.log.info("\tmode[{}]        = {}×{}\t{}Hz,\t\"{s}\"", .{ i, mode.hdisplay, mode.vdisplay, mode.vrefresh, std.mem.spanZ(@ptrCast(*const [32:0]u8, &mode.name)) });
            }

            for (connector.available_encoders) |encoder, i| {
                std.log.info("\tencoder[{}]     = {}", .{ i, encoder });
            }

            //Check if the connector is OK to use (connected to something)
            if (connector.available_encoders.len < 1 or connector.modes.len < 1 or connector.current_encoder == null or connector.connection == null) {
                std.log.info("connector[{}]: Not connected", .{connector_index});
                continue;
            } else {
                std.log.info("connector[{}]: connected, {}×{}", .{
                    connector_index,
                    connector.modes[0].hdisplay,
                    connector.modes[0].vdisplay,
                });
            }

            //If we create the buffer later, we can get the size of the screen first.
            //This must be a valid mode, so it's probably best to do this after we find
            //a valid crtc with modes.
            var create_dumb = c.drm_mode_create_dumb{
                .width = connector.modes[0].hdisplay,
                .height = connector.modes[0].vdisplay,
                .bpp = 32,
                .flags = 0,
                .pitch = 0,
                .size = 0,
                .handle = 0,
            };

            var res: usize = undefined;

            res = ioctl(card.file.handle, c.DRM_IOCTL_MODE_CREATE_DUMB, @ptrToInt(&create_dumb));
            std.log.warn("ioctl({}) = {}", .{ @src(), res });

            std.debug.print("{}: dumb.create = {}\n", .{ connector_index, create_dumb });

            var cmd_dumb = c.drm_mode_fb_cmd{
                .handle = create_dumb.handle,
                .width = create_dumb.width,
                .height = create_dumb.height,
                .bpp = create_dumb.bpp,
                .pitch = create_dumb.pitch,
                .depth = 24,

                .fb_id = 0,
            };
            res = ioctl(card.file.handle, c.DRM_IOCTL_MODE_ADDFB, @ptrToInt(&cmd_dumb));
            std.log.warn("ioctl({}) = {}", .{ @src().line, res });

            std.debug.print("{}: dumb.addfb = {}\n", .{ connector_index, cmd_dumb });

            var map_dumb = c.drm_mode_map_dumb{
                .handle = create_dumb.handle,

                .pad = 0,
                .offset = 0,
            };
            res = ioctl(card.file.handle, c.DRM_IOCTL_MODE_MAP_DUMB, @ptrToInt(&map_dumb));
            std.log.warn("ioctl({}) = {}", .{ @src().line, res });

            std.debug.print("{}: dumb.map = {}\n", .{ connector_index, map_dumb });

            var fb = Framebuffer{
                .base = try std.os.mmap(
                    null,
                    create_dumb.size,
                    std.os.linux.PROT_READ | std.os.linux.PROT_WRITE,
                    std.os.linux.MAP_SHARED,
                    card.file.handle,
                    map_dumb.offset,
                ),
                .width = @intCast(usize, create_dumb.width),
                .height = @intCast(usize, create_dumb.height),
            };

            // //------------------------------------------------------------------------------
            // //Kernel Mode Setting (KMS)
            // //------------------------------------------------------------------------------

            // std.log.info("{}: {} : mode: {}, prop: {}, enc: {}", .{ i, conn.connection, conn.count_modes, conn.count_props, conn.count_encoders });
            // std.log.info("{}: modes: {}x{} FB: {*}", .{ i, conn_mode_buf[0].hdisplay, conn_mode_buf[0].vdisplay, framebuffers[i].base });

            var enc = std.mem.zeroes(c.drm_mode_get_encoder);

            enc.encoder_id = @truncate(c_uint, @enumToInt(connector.current_encoder.?));
            res = ioctl(card.file.handle, c.DRM_IOCTL_MODE_GETENCODER, @ptrToInt(&enc)); //get encoder
            std.log.warn("ioctl({}) = {}", .{ @src().line, res });

            std.log.info("\tencoder = {}", .{enc});

            var crtc = std.mem.zeroes(c.drm_mode_crtc);

            crtc.crtc_id = enc.crtc_id;
            res = ioctl(card.file.handle, c.DRM_IOCTL_MODE_GETCRTC, @ptrToInt(&crtc));
            std.log.warn("ioctl({}) = {}", .{ @src().line, res });

            std.log.info("crtc = {}", .{crtc});

            crtc.fb_id = cmd_dumb.fb_id;
            crtc.set_connectors_ptr = @ptrToInt(&connector_id);
            crtc.count_connectors = 1;
            crtc.mode = connector.modes[0];
            crtc.mode_valid = 1;
            res = ioctl(card.file.handle, c.DRM_IOCTL_MODE_SETCRTC, @ptrToInt(&crtc));
            std.log.warn("ioctl({}) = {}", .{ @src().line, res });

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
        var random = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp()));

        var i: usize = 0;
        while (i < 30) : (i += 1) {
            var j: usize = 0;
            for (framebuffers) |fb_or_null| {
                const fb = fb_or_null orelse continue;

                const base_col: u32 = (random.random.int(u32)) & 0x00ffffff;

                var y: usize = 0;
                while (y < fb.height) : (y += 1) {
                    var x: usize = 0;
                    while (x < fb.width) : (x += 1) {
                        const col = base_col ^
                            @truncate(u32, (x & 0xFF) << 0) ^
                            @truncate(u32, (y & 0xFF) << 8);

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
