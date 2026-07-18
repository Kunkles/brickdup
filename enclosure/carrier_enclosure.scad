// carrier_enclosure.scad — ROUGH v0.2 shell for the brickdup v0.2 carrier board
// ---------------------------------------------------------------------------
// Rounded "pillowed" styling pass (ref: enclosure/reference/antenna_mount_ref.png)
// on the concept model per enclosure/CARRIER_ENCLOSURE.md. Still NOT print-ready:
// every ‹MEASURE› default needs calipers when boards + hardware arrive.
//
//   part = "assembly" | "base" | "lid"
//
// Key facts wired in from the project:
//   board 62 x 44 x 1.6, M2 holes at (3.5,3.5)(58.5,3.5)(3.5,40.5)(58.5,40.5)
//   socket stack: 8.5 socket + 2.5 header plastic + 1.6 heltec pcb + ~3.5 OLED
//   LiPo bay under WEST half of board, bosses 8 tall (pouch 50x34x7)
//   antenna: SMA bulkhead in NW pocket, axis EAST, 50mm whip (incl male, D8)
//            riding a FULL-LENGTH guard channel outside the north wall
//   east wall: LEMO entry + USB-C access;  buttons/switch: wired, lid flexures

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
r_out   = 4.0;                          // outer pillow radius (the sexy)
r_in    = 2.0;                          // cavity corner radius

/* ---------------- antenna channel (north wall) --------------------------- */
ant_d      = 8;      // whip diameter (listing) ‹MEASURE›
ant_len    = 50;     // whip incl. SMA male (listing)
sma_hole   = 6.5;    // ‹MEASURE›
sma_barrel = 8;      // ‹MEASURE›
ch_w       = ant_d + 3;
ch_wall    = 2.4;
pocket_l   = 14;

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
od = id + 2*wall;
inner_h = boss_h + bt + stack_h + top_air;
base_h  = floor_t + inner_h;
ant_z   = floor_t + boss_h + bt + 9;    // ‹MEASURE›
bx0 = wall + tol;
by0 = wall + tol;
wing_d = ch_w + ch_wall;                // antenna lobe depth beyond north wall

$fn = $preview ? 28 : 56;

/* ============ rounded primitives ========================================= */
// pillowed open-top tub solid: rounded bottom edges, vertical rim
module pillow_solid(w, d, h, r) {
    hull() for (x = [r, w - r], y = [r, d - r]) {
        translate([x, y, r]) sphere(r);
        translate([x, y, h - 1]) cylinder(r = r, h = 1);
    }
}
// rounded-plan slab (vertical corners only)
module rslab(w, d, h, r) {
    hull() for (x = [r, w - r], y = [r, d - r])
        translate([x, y, 0]) cylinder(r = r, h = h);
}
// capsule along X (rounded-end slot cutter)
module capsule_x(x0, x1, y, z, r) {
    hull() { translate([x0, y, z]) sphere(r); translate([x1, y, z]) sphere(r); }
}

/* ============ base ======================================================== */
module base_solid() {
    // main pillowed tub blended with the antenna lobe via a shared hull-lobe
    pillow_solid(ow, od, base_h, r_out);
    // antenna lobe: pillowed bar riding the north wall, blended into the body
    hull() {
        translate([0, od - 6, 0]) pillow_solid(ow, 6, base_h, 3);
        translate([0, od - 1, 0]) pillow_solid(ow, wing_d + 1, ant_z + ch_w/2 + 3, 3);
    }
}

module base() {
    difference() {
        base_solid();
        // cavity (rounded corners)
        translate([wall, wall, floor_t]) rslab(iw, id, base_h, r_in);
        // antenna trough: capsule bore + open top, x from pocket face to east
        capsule_x(pocket_l - 2, ow - 2, od + ch_w/2, ant_z, ch_w/2);
        translate([pocket_l - 2, od + ch_w/2 - ant_d/2 - 0.5, ant_z])
            cube([ow - pocket_l, ant_d + 1, base_h]);           // top opening
        // SMA bulkhead bore through the pocket's east face
        translate([pocket_l - 8, od + ch_w/2, ant_z])
            rotate([0, 90, 0]) cylinder(d = sma_hole, h = 8);
        // pocket void (nut + pigtail room) inside the lobe's west end
        translate([2.5, od + 1.5, ant_z - 6]) cube([pocket_l - 12, ch_w - 2, 12]);
        // pigtail pass from case interior into the pocket void
        translate([wall + 2, od - wall - 1, ant_z - 4]) cube([8, wall + 3, 8]);
        // LEMO hole, east wall (south half)
        translate([ow + 1, wall + 11, lemo_z])
            rotate([0, -90, 0]) cylinder(d = lemo_hole, h = wall + 4);
        // USB-C slot (rounded ends), east wall at module height
        hull() for (yy = [od/2 - usb_w/2 + usb_h/2, od/2 + usb_w/2 - usb_h/2])
            translate([ow - wall - 2, yy, floor_t + boss_h + bt + 11.5 + usb_h/2])
                rotate([0, 90, 0]) cylinder(d = usb_h, h = wall + 4);
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
        // pillowed cap: vertical skirt below, rounded top edges above
        hull() for (x = [r_out, ow - r_out], y = [r_out, od - r_out]) {
            translate([x, y, lid_t - r_out/1.6])
                scale([1, 1, 0.6]) sphere(r_out);
            translate([x, y, 0]) cylinder(r = r_out, h = 1);
        }
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
    // inner skirt (engages the tub rim)
    translate([wall/2 + 0.2, wall/2 + 0.2, -lip_h]) difference() {
        rslab(ow - wall - 0.4, od - wall - 0.4, lip_h, r_in);
        translate([wall/2, wall/2, -1])
            rslab(ow - 2*wall - 0.4, od - 2*wall - 0.4, lip_h + 2, r_in);
    }
    // press bosses under the flexure tabs
    for (fx = [18, 36])
        translate([fx + 2 + flex_l/2, by0 + 10 + flex_w/2, -3]) cylinder(d = 4, h = 3);
}

/* ============ ghosts ====================================================== */
module antenna_ghost() {
    color("black", 0.6)
        translate([pocket_l - 8 + 8 + sma_barrel, od + ch_w/2, ant_z])
            rotate([0, 90, 0]) cylinder(d = ant_d, h = ant_len - 8);
}

if (part == "base") base();
if (part == "lid") lid();
if (part == "assembly") {
    base();
    color("steelblue", 0.5) translate([0, 0, base_h + lip_h + 3]) lid();
    antenna_ghost();
    color("green", 0.4) translate([bx0, by0, floor_t + boss_h]) cube([bw, bd, bt]);
    color("orange", 0.3)
        translate([bx0 + 5.5, by0 + 6.7, floor_t + boss_h + bt + 11])
            cube([50.2, 25.5, 4.5]);
}
