// carrier_enclosure.scad — v0.4 shell for the brickdup v0.2 carrier board
// ---------------------------------------------------------------------------
// H1-styled build (donor: enclosure/H1_V1.2.3mf, cradle reference mesh at
// enclosure/reference/h1_antenna_cradle.stl). Carrier-sized, parametric.
//
//   part = "assembly" | "base" | "lid"
//
// Layout (verified facts wired in):
//   board 62 x 44 x 1.6, M2 @ (3.5,3.5)(58.5,3.5)(3.5,40.5)(58.5,40.5)
//   socket stack ~15.5 over the board; LiPo bay (50x34x7) under WEST half
//   antenna: full-width north compartment — covered front/ends/roof, roof
//   FLUSH with lid top, underside OPEN; SMA saddle + horn at the WEST end
//   (H1-style cradle); 50mm whip (incl SMA male), D8
//   east wall: LEMO + USB-C;  buttons/switch: wired -> lid flexure wells

part = "assembly"; // [assembly, base, lid]

/* ---------------- board + stack (verified) ------------------------------- */
bw = 62;  bd = 44;  bt = 1.6;
hole_in = 3.5;
boss_h  = 8;
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
usb_w = 11; usb_h = 5;                  // ‹MEASURE›

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

/* ============ base ======================================================== */
module base() {
    difference() {
        union() {
            pillow_solid(ow, od2, base_h, r_out);
            // compartment riser to the lid-top plane (flush, continuous)
            translate([0, od - 2, 0]) dome_slab(ow, comp_d + 2, z_top, r_out);
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
        // USB-C pill slot, east wall
        hull() for (yy = [od/2 - usb_w/2 + usb_h/2, od/2 + usb_w/2 - usb_h/2])
            translate([ow - wall - 2, yy, floor_t + boss_h + bt + 11.5 + usb_h/2])
                rotate([0, 90, 0]) cylinder(d = usb_h, h = wall + 4);
    }
    // ---- H1-style cradle at the WEST end of the channel ----
    // seat plate + horn sweep + half-round saddle under the jack line
    difference() {
        union() {
            // seat block the bulkhead mounts through
            translate([end_cap - 1, od, z_ax - 6.5])
                cube([saddle_x - end_cap + 1, comp_d - wall, z_ceil - z_ax + 6.5]);
            // horn: quarter-round sweep from the west end cap up to the roof
            hull() {
                translate([end_cap - 1, od, z_ceil - 1])
                    cube([2, comp_d - wall, 1]);
                translate([saddle_x + 6, od, z_ceil - 1])
                    cube([1, comp_d - wall, 1]);
                translate([end_cap - 1, od, z_ax - 6.5])
                    cube([2, comp_d - wall, 1]);
            }
        }
        // the bulkhead bore
        translate([saddle_x - 6.5, y_ax, z_ax])
            rotate([0, 90, 0]) cylinder(d = sma_hole, h = 10);
        // saddle scoop: half-cylinder opening DOWNWARD around the barrel/nut
        translate([saddle_x - 0.5, y_ax, z_ax])
            rotate([0, 90, 0]) cylinder(d = 13, h = 10);
        translate([saddle_x - 0.5, y_ax - 6.5, z_ax - 12])
            cube([10, 13, 12]);
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
        dome_slab(ow, lid_d, lid_t, r_out);
        // H1-style recessed bezel frame, then the window through its floor
        translate([bx0 + 30 - oled_w/2 - bezel, by0 + 22 - oled_d/2 - bezel, lid_t - 1.2])
            rslab(oled_w + 2*bezel, oled_d + 2*bezel, 2, oled_r + bezel/2);
        translate([bx0 + 30 - oled_w/2, by0 + 22 - oled_d/2, -1])
            rslab(oled_w, oled_d, lid_t + 3, oled_r);
        // flexure button wells (recessed rounded squares, H1 well styling)
        for (fx = [16, 38]) {
            translate([fx - well_pad, by0 + 8 - well_pad, lid_t - 1.0])
                rslab(flex_l + 4 + 2*well_pad, flex_w + 4 + 2*well_pad, 2, 3);
            translate([fx, by0 + 8, -1]) difference() {
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
        translate([fx + 2 + flex_l/2, by0 + 10 + flex_w/2, -3]) cylinder(d = 4, h = 3);
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
