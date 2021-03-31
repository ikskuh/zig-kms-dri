const std = @import("std");

const c = @import("c.zig");

const ioctl = std.os.linux.ioctl;

const Card = @This();

file: std.fs.File,

pub fn open(path: []const u8) !Card {
    return Card{
        .file = try std.fs.cwd().openFile(path, .{ .read = true, .write = true }),
    };
}

pub fn close(self: *Card) void {
    self.file.close();
    self.* = undefined;
}

pub fn getMaster(self: *Card) !void {
    _ = ioctl(self.file.handle, c.DRM_IOCTL_SET_MASTER, 0);
}

pub fn dropMaster(self: *Card) !void {
    _ = ioctl(self.file.handle, c.DRM_IOCTL_DROP_MASTER, 0);
}

pub fn getResourceHandles(self: Card, allocator: *std.mem.Allocator) !ResourceHandles {
    var res = std.mem.zeroes(c.drm_mode_card_res);
    _ = ioctl(self.file.handle, c.DRM_IOCTL_MODE_GETRESOURCES, @ptrToInt(&res));

    var fbs = try allocator.alloc(FramebufferID, res.count_fbs);
    errdefer allocator.free(fbs);

    var encoders = try allocator.alloc(EncoderID, res.count_encoders);
    errdefer allocator.free(encoders);

    var crtcs = try allocator.alloc(CrtcID, res.count_crtcs);
    errdefer allocator.free(crtcs);

    var connectors = try allocator.alloc(ConnectorID, res.count_connectors);
    errdefer allocator.free(connectors);

    res.fb_id_ptr = @ptrToInt(fbs.ptr);
    res.crtc_id_ptr = @ptrToInt(crtcs.ptr);
    res.connector_id_ptr = @ptrToInt(connectors.ptr);
    res.encoder_id_ptr = @ptrToInt(encoders.ptr);

    _ = ioctl(self.file.handle, c.DRM_IOCTL_MODE_GETRESOURCES, @ptrToInt(&res));

    return ResourceHandles{
        .allocator = allocator,
        .fbs = fbs,
        .encoders = encoders,
        .crtcs = crtcs,
        .connectors = connectors,
    };
}

pub fn getConnector(self: Card, allocator: *std.mem.Allocator, connector_id: ConnectorID) !Connector {
    var conn = std.mem.zeroes(c.drm_mode_get_connector);

    conn.connector_id = @truncate(c_uint, @enumToInt(connector_id));

    _ = ioctl(self.file.handle, c.DRM_IOCTL_MODE_GETCONNECTOR, @ptrToInt(&conn)); //get connector resource counts

    //    struct_drm_mode_get_connector{ .encoders_ptr = 0,
    //  .modes_ptr = 0,
    //  .props_ptr = 0,
    //  .prop_values_ptr = 0,
    //  .count_modes = 10,
    //  .count_props = 15,
    //  .count_encoders = 1,
    //  .encoder_id = 77,
    //  .connector_id = 78,
    //  .connector_type = 14,
    //  .connector_type_id = 1,
    //  .connection = 1,
    //  .mm_width = 340,
    //  .mm_height = 190,
    //  .subpixel = 0,
    //  .pad = 0 }

    const modes = try allocator.alloc(c.drm_mode_modeinfo, conn.count_modes);
    errdefer allocator.free(modes);

    var encoders = try allocator.alloc(EncoderID, conn.count_encoders);
    errdefer allocator.free(encoders);

    var property_keys = try allocator.alloc(PropertyID, conn.count_props);
    errdefer allocator.free(property_keys);

    var property_values = try allocator.alloc(u64, conn.count_props);
    errdefer allocator.free(property_values);

    conn.modes_ptr = @ptrToInt(modes.ptr);
    conn.props_ptr = @ptrToInt(property_keys.ptr);
    conn.prop_values_ptr = @ptrToInt(property_values.ptr);
    conn.encoders_ptr = @ptrToInt(encoders.ptr);

    _ = ioctl(self.file.handle, c.DRM_IOCTL_MODE_GETCONNECTOR, @ptrToInt(&conn)); //get connector resources

    return Connector{
        .allocator = allocator,

        .current_encoder = if (conn.encoder_id > 0) @intToEnum(EncoderID, conn.encoder_id) else null,

        .connection = if (conn.connection > 0) conn.connection else null,

        .physical_dimension = Size{
            .width = conn.mm_width,
            .height = conn.mm_height,
        },

        .modes = modes,
        .property_keys = property_keys,
        .property_values = property_values,
        .available_encoders = encoders,
    };
}

pub const FramebufferID = extern enum(u64) { _ };
pub const ConnectorID = extern enum(u64) { _ };
pub const EncoderID = extern enum(u64) { _ };
pub const CrtcID = extern enum(u64) { _ };
pub const PropertyID = extern enum(u64) { _ };

pub const ResourceHandles = struct {
    allocator: *std.mem.Allocator,

    fbs: []FramebufferID,
    encoders: []EncoderID,
    crtcs: []CrtcID,
    connectors: []ConnectorID,

    pub fn deinit(self: *ResourceHandles) void {
        self.allocator.free(self.fbs);
        self.allocator.free(self.encoders);
        self.allocator.free(self.crtcs);
        self.allocator.free(self.connectors);
        self.* = undefined;
    }
};

pub const Connector = struct {
    allocator: *std.mem.Allocator,

    current_encoder: ?EncoderID,

    connection: ?usize,

    /// physical dimensions in millimeters
    physical_dimension: Size,

    modes: []c.drm_mode_modeinfo,
    available_encoders: []EncoderID,
    property_keys: []PropertyID,
    property_values: []u64,

    pub fn deinit(self: *Connector) void {
        self.allocator.free(self.modes);
        self.allocator.free(self.available_encoders);
        self.allocator.free(self.property_keys);
        self.allocator.free(self.property_values);
        self.* = undefined;
    }

    pub fn getProperty(self: Connector, name: PropertyID) ?u64 {
        for (self.property_keys) |k, i| {
            if (k == name)
                return self.property_values[i];
        }
        return null;
    }

    pub fn setProperty(self: Connector, name: PropertyID, value: u64) !void {
        for (self.property_keys) |k, i| {
            if (k == name) {
                self.property_values[i] = value;
                return;
            }
        }
        return error.PropertyNotFound;
    }
};

pub const Size = struct {
    width: usize,
    height: usize,
};
