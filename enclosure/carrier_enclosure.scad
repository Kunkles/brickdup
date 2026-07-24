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
//   east wall: LEMO double-D (no USB opening this version — lid-off/OTA)
//   west wall: SMA bulkhead;  lid: OLED window only (button wells dropped)

part = "assembly"; // [assembly, base, lid]
ghosts = true;     // antenna/board/module reference ghosts in the assembly view

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

/* ---------------- lid ------------------------------------------------------ */
oled_w = 28; oled_d = 13; oled_r = 2.5; // ‹MEASURE›
// (flexure button wells dropped this version — buttons are wired, wells can
//  come back anywhere on the lid when the button plan firms up)

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
        // (no USB opening this version — lid-off USB for flashing, OTA after;
        //  the notch geometry lives in git history if it comes back)
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
    }
    // inner skirt
    translate([wall + 0.3, wall + 0.3, -lip_h]) difference() {
        rslab(iw - 0.6, id - 0.6, lip_h, r_in);
        translate([wall, wall, -1]) rslab(iw - 0.6 - 2*wall, id - 0.6 - 2*wall, lip_h + 2, r_in);
    }
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
    if (ghosts) {
        antenna_ghost();
        color("green", 0.4) translate([bx0, by0, floor_t + boss_h]) cube([bw, bd, bt]);
        color("orange", 0.3)
            translate([bx0 + 5.5, by0 + 6.7, floor_t + boss_h + bt + 11])
                cube([50.2, 25.5, 4.5]);
    }
}
