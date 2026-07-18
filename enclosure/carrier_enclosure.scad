// carrier_enclosure.scad — v0.4 shell for the brickdup v0.2 carrier board
// ---------------------------------------------------------------------------
// H1-styled build (donor: enclosure/H1_V1.2.3mf, cradle reference mesh at
// enclosure/reference/h1_antenna_cradle.stl). Carrier-sized, parametric.
//
//   part = "assembly" | "base" | "lid"
//
// Layout (verified facts wired in):
//   board 62 x 44 x 1.6, M2 @ (3.5,3.5)(58.5,3.5)(3.5,40.5)(58.5,40.5)
//   socket stack ~15.5 over the board; LiPo bay = FULL board footprint under
//   the standoffs — MakerHawk 1100 (41.4 x 25.15 x 10.25 calipered) + THT
//   stub clearance -> boss_h 12.5; pouch placeable anywhere (west preferred)
//   antenna: full-width north compartment — covered front/ends/roof, roof
//   FLUSH with lid top, underside OPEN; SMA saddle + horn at the WEST end
//   (H1-style cradle); 50mm whip (incl SMA male), D8
//   east wall: LEMO + USB-C;  buttons/switch: wired -> lid flexure wells

part = "assembly"; // [assembly, base, lid]

/* ---------------- board + stack (verified) ------------------------------- */
bw = 62;  bd = 44;  bt = 1.6;
hole_in = 3.5;
// Full-board under-floor LiPo bay: pouch 10.25 thick + THT pin stubs
// protruding below the board (sockets/JSTs, ~1.5 assumed ‹MEASURE›) + margin.
// Never let stubs touch the pouch.
boss_h  = 12.5;
stack_h = 15.5;                         // ‹MEASURE›
top_air = 2.5;

/* ---------------- shell ---------------------------------------------------- */
wall    = 2.4;
floor_t = 2.0;
tol     = 0.5;
lid_t   = 3.2;
lip_h   = 4;
r_out   = 6.0;                          // H1-ish plan radius
r_in    = 2.5;

/* ---------------- antenna compartment (north) ----------------------------- */
ant_d      = 8;      // ‹MEASURE›
ant_len    = 50;
sma_hole   = 6.5;    // ‹MEASURE›
sma_barrel = 8;      // ‹MEASURE›
comp_d     = ant_d + 4.5;
end_cap    = 5;

/* ---------------- east wall ------------------------------------------------ */
lemo_hole = 12;      // ‹MEASURE — carry v11›
lemo_z    = 12;      // ‹MEASURE›
// USB-C port face sits ~9mm behind the outer wall (module 6.3mm inboard of
// board edge + gap + wall) -> the cable OVERMOLD must pass through the wall
// to seat the plug. Slot is overmold-sized, centred on the plug axis.
// Best-effort: chunky overmolds won't fit -> lid-off USB, OTA for the field.
usb_w = 13; usb_h = 8;                  // ‹MEASURE - overmold, not shell›
usb_z = 13.6;                           // ‹MEASURE - plug axis above board top›

/* ---------------- lid (H1 face language) ----------------------------------- */
oled_w = 28; oled_d = 13; oled_r = 2.5; // ‹MEASURE›
bezel  = 3.2;                           // recessed frame around the window
flex_l = 15; flex_w = 10;               // flexure tab
well_pad = 2.6;                         // recessed well border around tabs

/* ---------------- derived -------------------------------------------------- */
iw = bw + 2*tol;
id = bd + 2*tol;
ow = iw + 2*wall;
od = id + 2*wall;
od2 = od + comp_d;
inner_h = boss_h + bt + stack_h + top_air;
base_h  = floor_t + inner_h;
z_top   = base_h + lid_t;
z_ceil  = z_top - wall;
z_ax    = z_ceil - ant_d/2 - 0.6;
y_ax    = od + (comp_d - wall)/2;
saddle_x = 15;                          // SMA seat plate east face (x)
bx0 = wall + tol;
by0 = wall + tol;

$fn = $preview ? 32 : 64;

/* ============ rounded primitives ========================================= */
module pillow_solid(w, d, h, r) {
    hull() for (x = [r, w - r], y = [r, d - r]) {
        translate([x, y, r]) sphere(r);
        translate([x, y, h - 1]) cylinder(r = r, h = 1);
    }
}
module rslab(w, d, h, r) {
    hull() for (x = [r, w - r], y = [r, d - r])
        translate([x, y, 0]) cylinder(r = r, h = h);
}
module dome_slab(w, d, h, r) {
    hull() for (x = [r, w - r], y = [r, d - r]) {
        translate([x, y, h - r/1.6]) scale([1, 1, 0.6]) sphere(r);
        translate([x, y, 0]) cylinder(r = r, h = 1);
    }
}
// H1-style cap: near-half-round top edge (full sphere roll-over)
module round_cap(w, d, h, r, re) {
    hull() for (x = [r, w - r], y = [r, d - r]) {
        translate([x, y, h - re]) sphere(re);
        translate([x, y, 0]) cylinder(r = r, h = 1);
    }
}

/* ============ base ======================================================== */
module base() {
    difference() {
        union() {
            pillow_solid(ow, od2, base_h, r_out);
            // compartment riser to the lid-top plane (flush, continuous)
            translate([0, od - 2, 0]) round_cap(ow, comp_d + 2, z_top, r_out, 3.0);
        }
        // main cavity
        translate([wall, wall, floor_t]) rslab(iw, id, base_h + lid_t, r_in);
        // antenna channel: full width, OPEN underside
        translate([end_cap, od, -1])
            cube([ow - 2*end_cap, comp_d - wall, z_ceil + 1]);
        // SMA bore through the saddle's seat plate
        translate([saddle_x - 6, y_ax, z_ax])
            rotate([0, 90, 0]) cylinder(d = sma_hole, h = 8);
        // pigtail pass through the shared wall (NW, high)
        translate([9, od - wall - 2, z_ax - 6]) cube([6, wall + 4, 5]);
        // LEMO hole, east wall (south half)
        translate([ow + 1, wall + 11, lemo_z])
            rotate([0, -90, 0]) cylinder(d = lemo_hole, h = wall + 4);
        // USB-C pill slot, east wall — overmold passes through; bottom edge
        // kept clear of the J1 JST plug + harness below (~5mm daylight)
        hull() for (yy = [od/2 - usb_w/2 + usb_h/2, od/2 + usb_w/2 - usb_h/2])
            translate([ow - wall - 2, yy, floor_t + boss_h + bt + usb_z])
                rotate([0, 90, 0]) cylinder(d = usb_h, h = wall + 4);
        // finger scallops on the south wall (H1 grip coves)
        for (sx = [20, 48])
            translate([sx, -7.4, -1]) cylinder(r = 8, h = base_h + 2);
    }
    // ---- H1-style cradle at the WEST end of the channel ----
    // seat plate + horn sweep + half-round saddle under the jack line
    difference() {
        union() {
            // seat block the bulkhead mounts through
            translate([end_cap - 1, od, z_ax - 6.5])
                cube([saddle_x - end_cap + 1, comp_d - wall, z_ceil - z_ax + 6.5]);
            // horn: block that gets a concave sweep carved below
            translate([end_cap - 1, od, z_ax - 6.5])
                cube([saddle_x - end_cap + 9, comp_d - wall, z_ceil - z_ax + 6.5]);
        }
        // the bulkhead bore
        translate([saddle_x - 6.5, y_ax, z_ax])
            rotate([0, 90, 0]) cylinder(d = sma_hole, h = 10);
        // saddle scoop: half-cylinder opening DOWNWARD around the barrel/nut
        translate([saddle_x - 0.5, y_ax, z_ax])
            rotate([0, 90, 0]) cylinder(d = 13, h = 10);
        translate([saddle_x - 0.5, y_ax - 6.5, z_ax - 12])
            cube([10, 13, 12]);
        // concave horn sweep (H1 swoop): big cylinder carve east of the seat
        translate([saddle_x + 22, od - 1, z_ax - 24])
            rotate([-90, 0, 0]) cylinder(r = 21, h = comp_d + 2);
        // keep the underside open behind the seat (nut/wrench access)
        translate([end_cap + 1, od + 1.5, z_ax - 7.5])
            cube([saddle_x - end_cap - 4.5, comp_d - wall - 3, 5.5]);
    }
    // 4x M2 bosses
    for (p = [[hole_in, hole_in], [bw - hole_in, hole_in],
              [hole_in, bd - hole_in], [bw - hole_in, bd - hole_in]])
        translate([bx0 + p[0], by0 + p[1], floor_t])
            difference() {
                cylinder(d = 7, h = boss_h);
                translate([0, 0, -1]) cylinder(d = 1.8, h = boss_h + 2);
            }
}

/* ============ lid (H1 face language) ====================================== */
lid_d = od - wall - 0.3;

module lid() {
    difference() {
        union() {
            round_cap(ow, lid_d, lid_t, r_out, 2.8);
            // raised face plateau flowing around the window (H1 contour)
            translate([10, by0 + 13, lid_t - 0.6])
                dome_slab(ow - 20, lid_d - by0 - 16, 2.0, 5);
        }
        // recessed bezel frame in the plateau, window through its floor
        translate([bx0 + 30 - oled_w/2 - bezel, by0 + 22 - oled_d/2 - bezel, lid_t + 0.2])
            rslab(oled_w + 2*bezel, oled_d + 2*bezel, 2.4, oled_r + bezel/2);
        translate([bx0 + 30 - oled_w/2, by0 + 22 - oled_d/2, -1])
            rslab(oled_w, oled_d, lid_t + 5, oled_r);
        // flexure button wells on the south strip (clear of the plateau)
        for (fx = [16, 38]) {
            translate([fx - well_pad, by0 + 1.5 - well_pad, lid_t - 1.0])
                rslab(flex_l + 4 + 2*well_pad, flex_w + 4 + 2*well_pad, 3, 3);
            translate([fx, by0 + 1.5, -1]) difference() {
                rslab(flex_l + 4, flex_w + 4, lid_t + 3, 2);
                translate([2, 2, -1]) rslab(flex_l, flex_w, lid_t + 5, 1.5);
            }
        }
    }
    // inner skirt
    translate([wall + 0.3, wall + 0.3, -lip_h]) difference() {
        rslab(iw - 0.6, id - 0.6, lip_h, r_in);
        translate([wall, wall, -1]) rslab(iw - 0.6 - 2*wall, id - 0.6 - 2*wall, lip_h + 2, r_in);
    }
    // press bosses under the tabs
    for (fx = [16, 38])
        translate([fx + 2 + flex_l/2, by0 + 3.5 + flex_w/2, -3]) cylinder(d = 4, h = 3);
}

/* ============ ghosts ====================================================== */
module antenna_ghost() {
    color("gold", 0.85)
        translate([saddle_x, y_ax, z_ax]) rotate([0, 90, 0]) cylinder(d = 7.5, h = sma_barrel);
    color("black", 0.75)
        translate([saddle_x + sma_barrel, y_ax, z_ax])
            rotate([0, 90, 0]) cylinder(d = ant_d, h = ant_len - 8);
}

if (part == "base") base();
if (part == "lid") lid();
if (part == "assembly") {
    base();
    color("steelblue", 0.55) translate([0, 0, base_h]) lid();
    antenna_ghost();
    color("green", 0.4) translate([bx0, by0, floor_t + boss_h]) cube([bw, bd, bt]);
    color("orange", 0.3)
        translate([bx0 + 5.5, by0 + 6.7, floor_t + boss_h + bt + 11])
            cube([50.2, 25.5, 4.5]);
}
