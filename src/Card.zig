const std = @import("std");

const c = @import("c.zig");

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

fn ioctl(self: Card, request: u32, arg: anytype) !void {
    const info = @typeInfo(@TypeOf(arg));
    const ptr: usize = if (info == .Int)
        @as(usize, arg)
    else if (info == .ComptimeInt)
        @as(usize, arg)
    else if (info == .Pointer)
        @ptrToInt(arg)
    else
        @compileError("Expects integer or pointer!");

    const ErrNo = extern enum(isize) {
        EPERM = 1,
        ENOENT = 2,
        ESRCH = 3,
        EINTR = 4,
        EIO = 5,
        ENXIO = 6,
        E2BIG = 7,
        ENOEXEC = 8,
        EBADF = 9,
        ECHILD = 10,
        EAGAIN = 11,
        ENOMEM = 12,
        EACCES = 13,
        EFAULT = 14,
        ENOTBLK = 15,
        EBUSY = 16,
        EEXIST = 17,
        EXDEV = 18,
        ENODEV = 19,
        ENOTDIR = 20,
        EISDIR = 21,
        EINVAL = 22,
        ENFILE = 23,
        EMFILE = 24,
        ENOTTY = 25,
        ETXTBSY = 26,
        EFBIG = 27,
        ENOSPC = 28,
        ESPIPE = 29,
        EROFS = 30,
        EMLINK = 31,
        EPIPE = 32,
        EDOM = 33,
        ERANGE = 34,
        EDEADLK = 35,
        ENAMETOOLONG = 36,
        ENOLCK = 37,
        ENOSYS = 38,
        ENOTEMPTY = 39,
        ELOOP = 40,
        ENOMSG = 42,
        EIDRM = 43,
        ECHRNG = 44,
        EL2NSYNC = 45,
        EL3HLT = 46,
        EL3RST = 47,
        ELNRNG = 48,
        EUNATCH = 49,
        ENOCSI = 50,
        EL2HLT = 51,
        EBADE = 52,
        EBADR = 53,
        EXFULL = 54,
        ENOANO = 55,
        EBADRQC = 56,
        EBADSLT = 57,
        EBFONT = 59,
        ENOSTR = 60,
        ENODATA = 61,
        ETIME = 62,
        ENOSR = 63,
        ENONET = 64,
        ENOPKG = 65,
        EREMOTE = 66,
        ENOLINK = 67,
        EADV = 68,
        ESRMNT = 69,
        ECOMM = 70,
        EPROTO = 71,
        EMULTIHOP = 72,
        EDOTDOT = 73,
        EBADMSG = 74,
        EOVERFLOW = 75,
        ENOTUNIQ = 76,
        EBADFD = 77,
        EREMCHG = 78,
        ELIBACC = 79,
        ELIBBAD = 80,
        ELIBSCN = 81,
        ELIBMAX = 82,
        ELIBEXEC = 83,
        EILSEQ = 84,
        ERESTART = 85,
        ESTRPIPE = 86,
        EUSERS = 87,
        ENOTSOCK = 88,
        EDESTADDRREQ = 89,
        EMSGSIZE = 90,
        EPROTOTYPE = 91,
        ENOPROTOOPT = 92,
        EPROTONOSUPPORT = 93,
        ESOCKTNOSUPPORT = 94,
        EOPNOTSUPP = 95,
        EPFNOSUPPORT = 96,
        EAFNOSUPPORT = 97,
        EADDRINUSE = 98,
        EADDRNOTAVAIL = 99,
        ENETDOWN = 100,
        ENETUNREACH = 101,
        ENETRESET = 102,
        ECONNABORTED = 103,
        ECONNRESET = 104,
        ENOBUFS = 105,
        EISCONN = 106,
        ENOTCONN = 107,
        ESHUTDOWN = 108,
        ETOOMANYREFS = 109,
        ETIMEDOUT = 110,
        ECONNREFUSED = 111,
        EHOSTDOWN = 112,
        EHOSTUNREACH = 113,
        EALREADY = 114,
        EINPROGRESS = 115,
        ESTALE = 116,
        EUCLEAN = 117,
        ENOTNAM = 118,
        ENAVAIL = 119,
        EISNAM = 120,
        EREMOTEIO = 121,
        EDQUOT = 122,
        ENOMEDIUM = 123,
        EMEDIUMTYPE = 124,
        ECANCELED = 125,
        ENOKEY = 126,
        EKEYEXPIRED = 127,
        EKEYREVOKED = 128,
        EKEYREJECTED = 129,
        EOWNERDEAD = 130,
        ENOTRECOVERABLE = 131,
        ERFKILL = 132,
        EHWPOISON = 133,
        ENSROK = 0,
        ENSRNODATA = 160,
        ENSRFORMERR = 161,
        ENSRSERVFAIL = 162,
        ENSRNOTFOUND = 163,
        ENSRNOTIMP = 164,
        ENSRREFUSED = 165,
        ENSRBADQUERY = 166,
        ENSRBADNAME = 167,
        ENSRBADFAMILY = 168,
        ENSRBADRESP = 169,
        ENSRCONNREFUSED = 170,
        ENSRTIMEOUT = 171,
        ENSROF = 172,
        ENSRFILE = 173,
        ENSRNOMEM = 174,
        ENSRDESTRUCTION = 175,
        ENSRQUERYDOMAINTOOLONG = 176,
        ENSRCNAMELOOP = 177,
        _,
    };

    const err = std.os.linux.ioctl(self.file.handle, request, ptr);
    if (err != 0) {
        std.log.emerg("ioctl failed: {}/{}/{}", .{ err, @bitCast(isize, err), @intToEnum(ErrNo, -@bitCast(isize, err)) });
        return error.UnknownError;
    }
}

pub fn getMaster(self: Card) !void {
    try self.ioctl(c.DRM_IOCTL_SET_MASTER, 0);
}

pub fn dropMaster(self: Card) !void {
    try self.ioctl(c.DRM_IOCTL_DROP_MASTER, 0);
}

pub fn getResourceHandles(self: Card, allocator: *std.mem.Allocator) !ResourceHandles {
    var res = std.mem.zeroes(drm_mode_card_res);
    try self.ioctl(c.DRM_IOCTL_MODE_GETRESOURCES, &res);

    var fbs = try allocator.allocAdvanced(FramebufferID, 8, res.count_fbs, .exact);
    errdefer allocator.free(fbs);

    var encoders = try allocator.allocAdvanced(EncoderID, 8, res.count_encoders, .exact);
    errdefer allocator.free(encoders);

    var crtcs = try allocator.allocAdvanced(CrtcID, 8, res.count_crtcs, .exact);
    errdefer allocator.free(crtcs);

    var connectors = try allocator.allocAdvanced(ConnectorID, 8, res.count_connectors, .exact);
    errdefer allocator.free(connectors);

    res.fb_id_ptr = @ptrToInt(fbs.ptr);
    res.crtc_id_ptr = @ptrToInt(crtcs.ptr);
    res.connector_id_ptr = @ptrToInt(connectors.ptr);
    res.encoder_id_ptr = @ptrToInt(encoders.ptr);

    try self.ioctl(c.DRM_IOCTL_MODE_GETRESOURCES, &res);

    return ResourceHandles{
        .allocator = allocator,
        .fbs = fbs,
        .encoders = encoders,
        .crtcs = crtcs,
        .connectors = connectors,
    };
}

pub fn getConnector(self: Card, allocator: *std.mem.Allocator, connector_id: ConnectorID) !Connector {
    var conn = std.mem.zeroes(drm_mode_get_connector);

    conn.connector_id = connector_id;

    try self.ioctl(c.DRM_IOCTL_MODE_GETCONNECTOR, &conn); //get connector resource counts

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

    const modes = try allocator.allocAdvanced(drm_mode_modeinfo, 8, conn.count_modes, .exact);
    errdefer allocator.free(modes);

    var encoders = try allocator.allocAdvanced(EncoderID, 8, conn.count_encoders, .exact);
    errdefer allocator.free(encoders);

    var property_keys = try allocator.allocAdvanced(PropertyID, 8, conn.count_props, .exact);
    errdefer allocator.free(property_keys);

    var property_values = try allocator.allocAdvanced(u64, 8, conn.count_props, .exact);
    errdefer allocator.free(property_values);

    conn.modes_ptr = @ptrToInt(modes.ptr);
    conn.props_ptr = @ptrToInt(property_keys.ptr);
    conn.prop_values_ptr = @ptrToInt(property_values.ptr);
    conn.encoders_ptr = @ptrToInt(encoders.ptr);

    try self.ioctl(c.DRM_IOCTL_MODE_GETCONNECTOR, &conn); //get connector resources

    return Connector{
        .allocator = allocator,

        .current_encoder = conn.encoder_id,

        .connection = conn.connection,

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

pub fn getEncoder(self: Card, encoder: EncoderID) !drm_mode_get_encoder {
    var enc = std.mem.zeroes(drm_mode_get_encoder);
    enc.encoder_id = encoder;

    try self.ioctl(c.DRM_IOCTL_MODE_GETENCODER, &enc); //get encoder

    return enc;
}

pub fn getCrtc(self: Card, id: CrtcID) !drm_mode_crtc {
    var crtc = std.mem.zeroes(drm_mode_crtc);
    crtc.crtc_id = id;

    try self.ioctl(c.DRM_IOCTL_MODE_GETCRTC, &crtc);

    return crtc;
}

pub fn setCrtc(self: Card, crtc: drm_mode_crtc) !void {
    try self.ioctl(c.DRM_IOCTL_MODE_SETCRTC, &crtc);
}

pub fn createDumbBuffer(self: Card, width: u32, height: u32, bpp: u8) !DumbBuffer {
    var create_dumb = drm_mode_create_dumb{
        .width = width,
        .height = height,
        .bpp = bpp,
        .flags = 0,
        .pitch = undefined,
        .size = undefined,
        .handle = undefined,
    };

    try self.ioctl(c.DRM_IOCTL_MODE_CREATE_DUMB, &create_dumb);

    return DumbBuffer{
        .card = self,
        .handle = create_dumb.handle,
        .width = width,
        .height = height,
        .bpp = bpp,
        .pitch = create_dumb.pitch,
        .size = create_dumb.size,
    };
}

pub const FramebufferID = extern enum(u32) { _ };
pub const ConnectorID = extern enum(u32) { _ };
pub const EncoderID = extern enum(u32) { _ };
pub const CrtcID = extern enum(u32) { _ };
pub const PropertyID = extern enum(u32) { _ };

pub const ResourceHandles = struct {
    allocator: *std.mem.Allocator,

    fbs: []align(8) FramebufferID,
    encoders: []align(8) EncoderID,
    crtcs: []align(8) CrtcID,
    connectors: []align(8) ConnectorID,

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

    connection: drm_connector_status,

    /// physical dimensions in millimeters
    physical_dimension: Size,

    modes: []drm_mode_modeinfo,
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

pub const DumbBufferID = extern enum(u32) { _ };
pub const DumbBuffer = struct {
    card: Card,
    handle: DumbBufferID,

    width: u32,
    height: u32,
    pitch: u32,
    size: u64,
    bpp: u8,

    pub fn deinit(self: *DumbBuffer) void {
        var destroy_buf = drm_mode_destroy_dumb{ .handle = self.handle };
        self.card.ioctl(c.DRM_IOCTL_MODE_DESTROY_DUMB, &destroy_buf) catch |e| std.log.emerg("Failed to destroy dumb buffer: {}", .{e});
        self.* = undefined;
    }

    pub fn addFB(self: DumbBuffer, depth: u32) !FramebufferID {
        var cmd_dumb = drm_mode_fb_cmd{
            .handle = self.handle,
            .width = self.width,
            .height = self.height,
            .bpp = self.bpp,
            .pitch = self.pitch,
            .depth = depth,

            .fb_id = undefined,
        };

        try self.card.ioctl(c.DRM_IOCTL_MODE_ADDFB, @ptrToInt(&cmd_dumb));

        return cmd_dumb.fb_id;
    }

    pub fn map(self: DumbBuffer) !u64 {
        var map_dumb = drm_mode_map_dumb{
            .handle = self.handle,
            .pad = 0,
            .offset = 0,
        };

        try self.card.ioctl(c.DRM_IOCTL_MODE_MAP_DUMB, @ptrToInt(&map_dumb));

        return map_dumb.offset;
    }
};

// create a dumb scanout buffer
const drm_mode_create_dumb = extern struct {
    height: u32,
    width: u32,
    bpp: u32,
    flags: u32,
    // handle, pitch, size will be returned
    handle: DumbBufferID,
    pitch: u32,
    size: u64,
};

// set up for mmap of a dumb scanout buffer
const drm_mode_map_dumb = extern struct {
    // Handle for the object being mapped.
    handle: DumbBufferID,
    pad: u32,
    // Fake offset to use for subsequent mmap call
    // This is a fixed-size type for 32/64 compatibility.
    offset: u64,
};

const drm_mode_destroy_dumb = extern struct {
    handle: DumbBufferID,
};

const drm_mode_fb_cmd = extern struct {
    fb_id: FramebufferID,
    width: u32,
    height: u32,
    pitch: u32,
    bpp: u32,
    depth: u32,

    handle: DumbBufferID,
};

const drm_mode_card_res = extern struct {
    fb_id_ptr: u64,
    crtc_id_ptr: u64,
    connector_id_ptr: u64,
    encoder_id_ptr: u64,
    count_fbs: u32,
    count_crtcs: u32,
    count_connectors: u32,
    count_encoders: u32,
    min_width: u32,
    max_width: u32,
    min_height: u32,
    max_height: u32,
};

const drm_mode_get_connector = extern struct {
    //  @encoders_ptr: Pointer to ``__u32`` array of object IDs.
    encoders_ptr: u64,
    // @modes_ptr: Pointer to struct drm_mode_modeinfo array.
    modes_ptr: u64,
    // @props_ptr: Pointer to ``__u32`` array of property IDs.
    props_ptr: u64,
    // @prop_values_ptr: Pointer to ``__u64`` array of property values.
    prop_values_ptr: u64,

    // @count_modes: Number of modes.
    count_modes: u32,
    // @count_props: Number of properties.
    count_props: u32,
    // @count_encoders: Number of encoders.
    count_encoders: u32,

    // @encoder_id: Object ID of the current encoder.
    encoder_id: EncoderID,
    // @connector_id: Object ID of the connector.
    connector_id: ConnectorID,

    // @connector_type: Type of the connector.
    connector_type: drm_connector_type,

    // @connector_type_id: Type-specific connector number.
    connector_type_id: u32,

    // @connection: Status of the connector.
    connection: drm_connector_status,

    mm_width: u32,
    mm_height: u32,

    subpixel: drm_subpixel_order,

    pad: u32,
};

const drm_subpixel_order = extern enum(u32) {
    unknown = 0,
    horizontal_rgb = 1,
    horizontal_bgr = 2,
    vertical_rgb = 3,
    vertical_bgr = 4,
    none = 5,
};

const drm_connector_type = extern enum(u32) {
    unknown = 0,
    vga = 1,
    dvii = 2,
    dvid = 3,
    dvia = 4,
    composite = 5,
    svideo = 6,
    lvds = 7,
    component = 8,
    @"9pindin" = 9,
    displayport = 10,
    hdmia = 11,
    hdmib = 12,
    tv = 13,
    edp = 14,
    virtual = 15,
    dsi = 16,
    dpi = 17,
    writeback = 18,
    spi = 19,
};

const drm_connector_status = extern enum(u32) {
    connected = 1,
    disconnected = 2,
    unknown = 3,
    _,
};

const drm_mode_modeinfo = extern struct {
    clock: u32,
    hdisplay: u16,
    hsync_start: u16,
    hsync_end: u16,
    htotal: u16,
    hskew: u16,
    vdisplay: u16,
    vsync_start: u16,
    vsync_end: u16,
    vtotal: u16,
    vscan: u16,

    vrefresh: u32,

    flags: u32,
    type: u32,
    name: [DRM_DISPLAY_MODE_LEN]u8,
};

const DRM_DISPLAY_MODE_LEN = 32;

const drm_mode_get_encoder = extern struct {
    encoder_id: EncoderID,
    encoder_type: u32,

    crtc_id: CrtcID,

    possible_crtcs: u32,
    possible_clones: u32,
};

pub const drm_mode_crtc = extern struct {
    set_connectors_ptr: u64,
    count_connectors: u32,

    crtc_id: CrtcID,
    fb_id: FramebufferID,

    x: u32, // x Position on the framebuffer
    y: u32, // y Position on the framebuffer

    gamma_size: u32,
    mode_valid: u32,
    mode: drm_mode_modeinfo,
};
