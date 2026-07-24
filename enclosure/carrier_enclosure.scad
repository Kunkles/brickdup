// carrier_enclosure.scad — v0.6 shell for the brickdup v0.2 carrier board
// ---------------------------------------------------------------------------
// Backed up 2026-07-24: the H1 style-donor experiment is GONE (sculpted
// faces, grip coves, antenna channel/cradle). Plain gently-rounded box,
// v11-style SMA bulkhead straight out the WEST wall.
//
//   part = "assembly" | "base" | "lid"
//
// Functional geometry kept (verified facts wired in):
//   board 62 x 44 x 1.6, M2 @ (3.5,3.5)(58.5,3.5)(3.5,40.5)(58.5,40.5)
//   socket stack ~15.5 over the board; LiPo bay = FULL board footprint under
//   the standoffs — MakerHawk 1100 (41.4 x 25.15 x 10.25 calipered) + THT
//   stub clearance -> boss_h 12.5; pouch placeable anywhere (west preferred)
//   east wall: LEMO double-D + USB overmold scoop;  west wall: SMA bulkhead
//   buttons/switch: wired -> lid flexure wells;  lid: OLED window

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
r_out   = 4.0;                          // gentle plan rounding, nothing sculpted
r_in    = 2.5;

/* ---------------- west wall — SMA bulkhead (v11 style) --------------------- */
sma_d    = 6.5;    // measured (v11) — bulkhead pass-through
sma_flat = 5.9;    // measured (v11) — single flat, on the bottom
sma_z    = 21.5;   // ‹MEASURE› — barrel clears board top (16.1) / module under (27.1)
ant_len  = 50;     // whip incl SMA male, for the assembly ghost only

/* ---------------- east wall ------------------------------------------------ */
lemo_d    = 8.9;     // measured (v11) — double-D panel hole
lemo_flat = 8.2;     // measured (v11) — across the flats, LEFT+RIGHT of hole
lemo_z    = 12;      // ‹MEASURE›
// USB-C port face sits ~9mm behind the outer wall (module 6.3mm inboard of
// board edge + gap + wall) -> the cable OVERMOLD must pass through the wall
// to seat the plug. Slot is overmold-sized, centred on the plug axis.
// Best-effort: chunky overmolds won't fit -> lid-off USB, OTA for the field.
usb_w = 13; usb_h = 8;                  // ‹MEASURE - overmold, not shell›
usb_z = 13.6;                           // ‹MEASURE - plug axis above board top›

/* ---------------- lid ------------------------------------------------------ */
oled_w = 28; oled_d = 13; oled_r = 2.5; // ‹MEASURE›
flex_l = 15; flex_w = 10;               // flexure tab
well_pad = 2.6;                         // recessed well border around tabs

/* ---------------- derived -------------------------------------------------- */
iw = bw + 2*tol;
id = bd + 2*tol;
ow = iw + 2*wall;
od = id + 2*wall;
inner_h = boss_h + bt + stack_h + top_air;
base_h  = floor_t + inner_h;
bx0 = wall + tol;
by0 = wall + tol;
sma_y = od/2;                           // ‹MEASURE› — keep clear of LiPo lead run

$fn = $preview ? 32 : 64;

/* ============ rounded primitives ========================================= */
module rslab(w, d, h, r) {
    hull() for (x = [r, w - r], y = [r, d - r])
        translate([x, y, 0]) cylinder(r = r, h = h);
}
// gentle rounded top edge (the one softening kept)
module round_cap(w, d, h, r, re) {
    hull() for (x = [r, w - r], y = [r, d - r]) {
        translate([x, y, h - re]) sphere(re);
        translate([x, y, 0]) cylinder(r = r, h = 1);
    }
}

/* ============ v11 measured connector holes (carried over 1:1) ============= */
// Both cut along +x from the translate origin (hole centre on the axis).
module lemo_hole_dd(len) {              // double-D: flats left+right
    intersection() {
        rotate([0, 90, 0]) cylinder(d = lemo_d, h = len);
        translate([0, -lemo_flat/2, -lemo_d/2]) cube([len, lemo_flat, lemo_d]);
    }
}
module sma_hole_flat(len) {             // single flat on the bottom
    intersection() {
        rotate([0, 90, 0]) cylinder(d = sma_d, h = len);
        translate([0, -sma_d/2, sma_d/2 - sma_flat]) cube([len, sma_d, sma_flat]);
    }
}

/* ============ base ======================================================== */
module base() {
    difference() {
        rslab(ow, od, base_h, r_out);
        // main cavity
        translate([wall, wall, floor_t]) rslab(iw, id, base_h, r_in);
        // SMA bulkhead, west wall (v11 keyed shape; nut + pigtail inside)
        translate([-2, sma_y, sma_z]) sma_hole_flat(wall + 4);
        // LEMO hole, east wall (south half) — v11 double-D, nut inside
        translate([ow - wall - 2, wall + 11, lemo_z]) lemo_hole_dd(wall + 4);
        // USB-C opening, east wall — the port axis is only ~4.4mm below the
        // rim, so a closed hole leaves a fragile sliver: cut a TOP-OPEN notch
        // instead (v11 approach); the lid roof closes it. Bottom edge kept
        // clear of the J1 JST plug + harness below (~5mm daylight).
        hull() for (yy = [od/2 - usb_w/2 + usb_h/2, od/2 + usb_w/2 - usb_h/2])
            translate([ow - wall - 2, yy, floor_t + boss_h + bt + usb_z])
                rotate([0, 90, 0]) cylinder(d = usb_h, h = wall + 4);
        translate([ow - wall - 2, od/2 - usb_w/2, floor_t + boss_h + bt + usb_z])
            cube([wall + 4, usb_w, base_h]);
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

/* ============ lid ========================================================= */
module lid() {
    difference() {
        round_cap(ow, od, lid_t, r_out, 2.8);
        // OLED window (plain through-cut)
        translate([bx0 + 30 - oled_w/2, by0 + 22 - oled_d/2, -1])
            rslab(oled_w, oled_d, lid_t + 2, oled_r);
        // flexure button wells on the south strip
        for (fx = [16, 38]) {
            translate([fx - well_pad, by0 + 1.5 - well_pad, lid_t - 1.0])
                rslab(flex_l + 4 + 2*well_pad, flex_w + 4 + 2*well_pad, 3, 3);
            translate([fx, by0 + 1.5, -1]) difference() {
                rslab(flex_l + 4, flex_w + 4, lid_t + 3, 2);
                translate([2, 2, -1]) rslab(flex_l, flex_w, lid_t + 5, 1.5);
            }
        }
    }
    // inner skirt — notched on the east side so the USB overmold can pass
    // under the lid into the wall notch
    difference() {
        translate([wall + 0.3, wall + 0.3, -lip_h]) difference() {
            rslab(iw - 0.6, id - 0.6, lip_h, r_in);
            translate([wall, wall, -1]) rslab(iw - 0.6 - 2*wall, id - 0.6 - 2*wall, lip_h + 2, r_in);
        }
        translate([ow - wall - 6, od/2 - usb_w/2 - 1, -lip_h - 1])
            cube([wall + 8, usb_w + 2, lip_h + 2]);
    }
    // press bosses under the tabs
    for (fx = [16, 38])
        translate([fx + 2 + flex_l/2, by0 + 3.5 + flex_w/2, -3]) cylinder(d = 4, h = 3);
}

/* ============ ghosts ====================================================== */
module antenna_ghost() {
    color("gold", 0.85)
        translate([-8, sma_y, sma_z]) rotate([0, 90, 0]) cylinder(d = 7.5, h = 8);
    color("black", 0.75)
        translate([-8 - (ant_len - 8), sma_y, sma_z])
            rotate([0, 90, 0]) cylinder(d = 8, h = ant_len - 8);
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
