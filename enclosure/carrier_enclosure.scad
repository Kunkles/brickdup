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
//   EAST BAY (20mm, v11 lesson): LEMO rear + nut, J1 mating plug + wire
//   U-turn — all east of the board so the under-board LiPo bay is untouched
//   east bay wall: LEMO double-D (no USB opening this version — lid-off/OTA)
//   west wall: SMA bulkhead;  lid: OLED window only (button wells dropped)

part = "assembly"; // [assembly, base, lid, print]
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
// cavity corner radius vs the SQUARE board corner: the fillet's 45deg point
// sits at wall + r*(1-1/sqrt(2)); it must stay <= wall + tol or the fillets
// wedge the board up off the bosses  =>  r_in*0.293 <= tol  =>  r_in <= 1.7
r_in    = 1.2;                          // 0.15mm corner margin at tol 0.5

/* ---------------- west wall — SMA bulkhead (v11 style) --------------------- */
sma_d    = 6.5;    // measured (v11) — bulkhead pass-through
sma_flat = 5.9;    // measured (v11) — single flat, on the bottom
sma_z    = 21.5;   // ‹MEASURE› — barrel clears board top (16.1) / module under (27.1)
ant_len  = 50;     // whip incl SMA male, for the assembly ghost only

/* ---------------- east bay + LEMO ------------------------------------------ */
// v11 lesson relearned: J1's mating JST plug + wire bend need ~10-12mm of
// air east of the board edge, and the LEMO body intrudes ~10mm past the
// wall (12mm deep, measured). A plain tub has 0.5mm there. The bay houses
// both, entirely east of the board — the under-board LiPo bay is untouched.
bay_l     = 20;      // v11 value (bay_l 12 -> 18 -> 20 history; wire U-turn room)
lemo_d    = 8.9;     // measured (v11) — double-D panel hole
lemo_flat = 8.2;     // measured (v11) — across the flats, LEFT+RIGHT of hole
lemo_z    = 14;      // ‹MEASURE› — nut (Ø13) clears the floor; mid-bay height


/* ---------------- lid ------------------------------------------------------ */
oled_w = 28; oled_d = 13; oled_r = 2.5; // ‹MEASURE›
// window centre in BOARD coords: the V3's OLED sits toward the ANTENNA
// (west) end of the module, not module-centre; y = module centreline
oled_cx = 25;                           // ‹MEASURE›
oled_cy = 19.5;                         // ‹MEASURE›
// (flexure button wells dropped this version — buttons are wired, wells can
//  come back anywhere on the lid when the button plan firms up)

/* ---------------- derived -------------------------------------------------- */
iw = bw + 2*tol;
id = bd + 2*tol;
cav_l = iw + bay_l;                     // board pocket + east bay, one cavity
ow = cav_l + 2*wall;
od = id + 2*wall;
inner_h = boss_h + bt + stack_h + top_air;
base_h  = floor_t + inner_h;
bx0 = wall + tol;
by0 = wall + tol;
// BOARD-Y -> CASE-Y MAPPING: board coords are KiCad-style (origin NW, +y
// SOUTH); case +y runs the other way. Every y taken from board coords MUST
// go through by() or it lands mirrored (this bug had the OLED window 5mm
// south and the LEMO 2.5mm off J1).
function by(yb) = by0 + bd - yb;
sma_y = od/2;                           // ‹MEASURE› — keep clear of LiPo lead run

/* ---------------- lid screws (M2 self-tap x4) ------------------------------ */
scr_pilot = 1.8;  scr_clear = 2.4;  scr_cs = 5.2;   // pilot / through / c'sink
post_d    = 6.0;
// east pair: full-height posts in the bay corners
post_e_x = ow - wall - 3;
post_e_y = [wall + 3, od - wall - 3];
// west pair: wall-hung above the board (board is wall-to-wall below z=16.1),
// 45deg gusset down to a sliver on the wall face keeps them printable
post_w_y = [wall + 4.5, od - wall - 4.5];
post_w_x = 4.4;                                      // protrudes to ~7.4 < module @8.4
post_w_z = 23;                                       // post bottom; gusset below

$fn = $preview ? 32 : 64;

/* ============ rounded primitives ========================================= */
module rslab(w, d, h, r) {
    hull() for (x = [r, w - r], y = [r, d - r])
        translate([x, y, 0]) cylinder(r = r, h = h);
}
// gentle rounded top edge (the one softening kept)
// clipped at z=0: the corner spheres bulge below zero (re > h-1) and an
// unclipped hull grows a hidden convex underside — flat bottom is required
// for the lid seat, the window through-cut, and the module clearance
module round_cap(w, d, h, r, re) {
    intersection() {
        hull() for (x = [r, w - r], y = [r, d - r]) {
            translate([x, y, h - re]) sphere(re);
            translate([x, y, 0]) cylinder(r = r, h = 1);
        }
        translate([-1, -1, 0]) cube([w + 2, d + 2, h + 1]);
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
        // main cavity: board pocket + east bay (LEMO rear, J1 plug, wires)
        translate([wall, wall, floor_t]) rslab(cav_l, id, base_h, r_in);
        // SMA bulkhead, west wall (v11 keyed shape; nut + pigtail inside)
        translate([-2, sma_y, sma_z]) sma_hole_flat(wall + 4);
        // LEMO hole, east bay wall — v11 double-D, nut inside the bay,
        // aligned with J1's mouth (board y 19.5, through the y-flip mapping)
        translate([ow - wall - 2, by(19.5), lemo_z]) lemo_hole_dd(wall + 4);
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
    // lid screw posts: east pair full height in the bay corners
    for (py = post_e_y)
        translate([post_e_x, py, floor_t]) difference() {
            cylinder(d = post_d, h = base_h - floor_t);
            translate([0, 0, base_h - floor_t - 8]) cylinder(d = scr_pilot, h = 9);
        }
    // west pair: hung on the wall above the board, gusset down to a sliver
    for (py = post_w_y) {
        difference() {
            union() {
                translate([post_w_x, py, post_w_z])
                    cylinder(d = post_d, h = base_h - post_w_z);
                hull() {
                    translate([post_w_x, py, post_w_z]) cylinder(d = post_d, h = 0.5);
                    translate([wall - 0.1, py - post_d/2, 16.3]) cube([0.7, post_d, 0.5]);
                }
            }
            translate([post_w_x, py, base_h - 8]) cylinder(d = scr_pilot, h = 9);
        }
    }
}

/* ============ lid ========================================================= */
module lid() {
    difference() {
        round_cap(ow, od, lid_t, r_out, 2.8);
        // OLED window (plain through-cut; y through the board-flip mapping)
        translate([bx0 + oled_cx - oled_w/2, by(oled_cy) - oled_d/2, -1])
            rslab(oled_w, oled_d, lid_t + 2, oled_r);
        // M2 clearance + countersink over the 4 posts
        for (p = [[post_e_x, post_e_y[0]], [post_e_x, post_e_y[1]],
                  [post_w_x, post_w_y[0]], [post_w_x, post_w_y[1]]]) {
            translate([p[0], p[1], -1]) cylinder(d = scr_clear, h = lid_t + 2);
            translate([p[0], p[1], lid_t - 1.4])
                cylinder(d1 = scr_clear, d2 = scr_cs, h = 1.5);
        }
    }
    // inner skirt, notched around the 4 screw posts
    difference() {
        translate([wall + 0.3, wall + 0.3, -lip_h]) difference() {
            rslab(cav_l - 0.6, id - 0.6, lip_h, r_in);
            translate([wall, wall, -1]) rslab(cav_l - 0.6 - 2*wall, id - 0.6 - 2*wall, lip_h + 2, r_in);
        }
        for (p = [[post_e_x, post_e_y[0]], [post_e_x, post_e_y[1]],
                  [post_w_x, post_w_y[0]], [post_w_x, post_w_y[1]]])
            translate([p[0], p[1], -lip_h - 1]) cylinder(d = post_d + 1.5, h = lip_h + 2);
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
if (part == "print") {   // both parts on the plate: lid top-face down
    base();
    translate([0, 2*od + 8, lid_t]) rotate([180, 0, 0]) lid();
}
if (part == "assembly") {
    base();
    color("steelblue", 0.55) translate([0, 0, base_h]) lid();
    if (ghosts) {
        antenna_ghost();
        color("green", 0.4) translate([bx0, by0, floor_t + boss_h]) cube([bw, bd, bt]);
        color("orange", 0.3)
            translate([bx0 + 5.5, by(32.2), floor_t + boss_h + bt + 11])
                cube([50.2, 25.5, 4.5]);
    }
}
