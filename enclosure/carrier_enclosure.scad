// carrier_enclosure.scad — ROUGH v0.3 shell for the brickdup v0.2 carrier board
// ---------------------------------------------------------------------------
// Antenna per reference (enclosure/reference/antenna_mount_ref.png):
//   a FULL-WIDTH antenna compartment integrated into the body's north side.
//   Covered on the front (north face), ends, and top — the compartment roof is
//   FLUSH with the lid's top plane. The whole UNDERSIDE is open: whip, SMA
//   male and the bulkhead connection are all reached from the back/bottom.
// Still NOT print-ready: every ‹MEASURE› default needs calipers.
//
//   part = "assembly" | "base" | "lid"

part = "assembly"; // [assembly, base, lid]

/* ---------------- board + stack (verified) ------------------------------- */
bw = 62;  bd = 44;  bt = 1.6;
hole_in = 3.5;
boss_h  = 8;
stack_h = 15.5;                         // ‹MEASURE›
top_air = 2.5;

/* ---------------- shell parameters --------------------------------------- */
wall    = 2.4;
floor_t = 2.0;
tol     = 0.5;
lid_t   = 3.0;
lip_h   = 4;
r_out   = 4.0;                          // outer pillow radius
r_in    = 2.0;

/* ---------------- antenna compartment (north side) ----------------------- */
ant_d      = 8;      // whip diameter (listing) ‹MEASURE›
ant_len    = 50;     // whip incl. SMA male (listing)
sma_hole   = 6.5;    // ‹MEASURE›
sma_barrel = 8;      // ‹MEASURE›
comp_d     = ant_d + 4.5;               // compartment depth beyond the tub (y)
end_cap    = 4;                         // solid ends of the compartment

/* ---------------- east wall features ------------------------------------- */
lemo_hole = 12;      // ‹MEASURE — carry v11›
lemo_z    = 12;      // ‹MEASURE›
usb_w = 11; usb_h = 5;                  // ‹MEASURE›

/* ---------------- lid ------------------------------------------------------ */
oled_w = 28; oled_d = 13;               // ‹MEASURE›
oled_r = 2.5;
flex_l = 14; flex_w = 9;

/* ---------------- derived ------------------------------------------------- */
iw = bw + 2*tol;
id = bd + 2*tol;
ow = iw + 2*wall;
od = id + 2*wall;                       // tub depth (south wall .. shared wall)
od2 = od + comp_d;                      // total depth incl. antenna compartment
inner_h = boss_h + bt + stack_h + top_air;
base_h  = floor_t + inner_h;            // tub rim (lid seats here)
z_top   = base_h + lid_t;               // lid top plane == compartment roof
z_ceil  = z_top - wall;                 // compartment ceiling (roof underside)
z_ax    = z_ceil - ant_d/2 - 0.6;       // whip axis, hanging under the roof
y_ax    = od + (comp_d - wall)/2;       // whip axis depth (mid-channel)
tower_l = 14;                           // west jack tower length (x)
bx0 = wall + tol;
by0 = wall + tol;

$fn = $preview ? 28 : 56;

/* ============ rounded primitives ========================================= */
module pillow_solid(w, d, h, r) {       // rounded bottom edges, vertical rim
    hull() for (x = [r, w - r], y = [r, d - r]) {
        translate([x, y, r]) sphere(r);
        translate([x, y, h - 1]) cylinder(r = r, h = 1);
    }
}
module rslab(w, d, h, r) {              // rounded-plan slab
    hull() for (x = [r, w - r], y = [r, d - r])
        translate([x, y, 0]) cylinder(r = r, h = h);
}
module dome_slab(w, d, h, r) {          // slab with domed top edges (lid style)
    hull() for (x = [r, w - r], y = [r, d - r]) {
        translate([x, y, h - r/1.6]) scale([1, 1, 0.6]) sphere(r);
        translate([x, y, 0]) cylinder(r = r, h = 1);
    }
}

/* ============ base ======================================================== */
module base() {
    difference() {
        union() {
            // pillowed tub spanning the FULL footprint incl. compartment strip
            pillow_solid(ow, od2, base_h, r_out);
            // compartment riser: north strip rising to the lid-top plane,
            // domed like the lid so the roof reads flush + continuous
            translate([0, od - 2, 0]) dome_slab(ow, comp_d + 2, z_top, r_out);
        }
        // main cavity (tub only — shared wall stays between cavity & channel)
        translate([wall, wall, floor_t]) rslab(iw, id, base_h + lid_t, r_in);
        // antenna channel: full width, open BOTTOM (cut from below through
        // everything except roof, north face, end caps, shared south wall)
        translate([end_cap, od, -1])
            cube([ow - 2*end_cap, comp_d - wall, z_ceil + 1]);
        // SMA bulkhead bore through the west tower's east face
        translate([tower_l - 8, y_ax, z_ax])
            rotate([0, 90, 0]) cylinder(d = sma_hole, h = 10);
        // pigtail bore through the shared wall into the cavity (NW, high)
        translate([9, od - wall - 2, z_ax - 6])
            cube([6, wall + 4, 5]);
        // LEMO hole, east wall (south half)
        translate([ow + 1, wall + 11, lemo_z])
            rotate([0, -90, 0]) cylinder(d = lemo_hole, h = wall + 4);
        // USB-C slot (rounded ends), east wall at module height
        hull() for (yy = [od/2 - usb_w/2 + usb_h/2, od/2 + usb_w/2 - usb_h/2])
            translate([ow - wall - 2, yy, floor_t + boss_h + bt + 11.5 + usb_h/2])
                rotate([0, 90, 0]) cylinder(d = usb_h, h = wall + 4);
    }
    // west jack tower inside the channel (hangs from the roof, holds the SMA)
    difference() {
        translate([end_cap - 0.5, od, z_ax - 7])
            cube([tower_l - end_cap + 0.5, comp_d - wall, z_ceil - z_ax + 7]);
        translate([tower_l - 8.5, y_ax, z_ax])
            rotate([0, 90, 0]) cylinder(d = sma_hole, h = 12);
        // keep the underside reachable: hollow the tower below the jack line
        translate([end_cap + 1, od + 1.5, z_ax - 8])
            cube([tower_l - end_cap - 4, comp_d - wall - 3, 6]);
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
lid_d = od - wall - 0.3;                // abuts the compartment's shared wall

module lid() {
    difference() {
        dome_slab(ow, lid_d, lid_t, r_out);
        // OLED window (rounded)
        translate([bx0 + 30 - oled_w/2, by0 + 22 - oled_d/2, -1])
            rslab(oled_w, oled_d, lid_t + 3, oled_r);
        // flexure U-slots, south half
        for (fx = [18, 36])
            translate([fx, by0 + 8, -1]) difference() {
                rslab(flex_l + 4, flex_w + 4, lid_t + 3, 2);
                translate([2, 2, -1]) rslab(flex_l, flex_w, lid_t + 5, 1.5);
            }
    }
    // inner skirt (sits just inside the cavity walls)
    translate([wall + 0.3, wall + 0.3, -lip_h]) difference() {
        rslab(iw - 0.6, id - 0.6, lip_h, r_in);
        translate([wall, wall, -1]) rslab(iw - 0.6 - 2*wall, id - 0.6 - 2*wall, lip_h + 2, r_in);
    }
    // press bosses under the flexure tabs
    for (fx = [18, 36])
        translate([fx + 2 + flex_l/2, by0 + 10 + flex_w/2, -3]) cylinder(d = 4, h = 3);
}

/* ============ ghosts ====================================================== */
module antenna_ghost() {
    color("gold", 0.85)
        translate([tower_l - 8 + 10, y_ax, z_ax])
            rotate([0, 90, 0]) cylinder(d = 7.5, h = sma_barrel);
    color("black", 0.75)
        translate([tower_l - 8 + 10 + sma_barrel, y_ax, z_ax])
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
