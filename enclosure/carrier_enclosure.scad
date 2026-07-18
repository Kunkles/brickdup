// carrier_enclosure.scad — ROUGH v0 shell for the brickdup v0.2 carrier board
// ---------------------------------------------------------------------------
// Concept model per enclosure/CARRIER_ENCLOSURE.md — geometry to look at and
// argue with, NOT print-ready. Every ‹MEASURE› default below needs a caliper
// pass when the boards + hardware arrive.
//
//   part = "assembly" | "base" | "lid"
//
// Coordinates: X east (board 0..62), Y north (board 0..44 with y=0 the SOUTH
// edge here — note the PCB file's y axis points south; this model uses y-up,
// mirror handled by symmetry since bosses are symmetric), Z up from outer floor.
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
bw = 62;  bd = 44;  bt = 1.6;          // board W(x) D(y) thickness
hole_in = 3.5;                          // M2 holes inset from board corners
boss_h  = 8;                            // raised: LiPo bay height under board
stack_h = 15.5;                         // socket 8.5 + male 2.5 + pcb 1.6 + parts/OLED ‹MEASURE›
top_air = 2.5;                          // clearance over the Heltec crown

/* ---------------- shell parameters --------------------------------------- */
wall  = 2.4;
floor_t = 2.0;
tol   = 0.5;                            // board-to-wall clearance each side
lid_t = 2.4;
lip_h = 4;                              // lid skirt engagement

/* ---------------- antenna channel (north wall) --------------------------- */
ant_d      = 8;      // whip diameter (listing: 8mm) ‹MEASURE›
ant_len    = 50;     // whip incl. SMA male (listing)
sma_hole   = 6.5;    // bulkhead thread hole ‹MEASURE›
sma_barrel = 10;     // female barrel protrusion into channel ‹MEASURE›
ch_w       = ant_d + 3;      // channel width (y, outward from north wall)
ch_wall    = 2.4;            // outer guard rail thickness
pocket_l   = 14;             // NW pocket block length (x) housing the jack

/* ---------------- east wall features ------------------------------------- */
lemo_hole = 12;      // LEMO panel hole ‹MEASURE — carry v11 values›
lemo_z    = 12;      // LEMO centre height above outer floor ‹MEASURE›
usb_w = 11; usb_h = 5;                  // USB-C access slot ‹MEASURE›

/* ---------------- lid: OLED window + flexure buttons ---------------------- */
oled_w = 28; oled_d = 13;               // window ‹MEASURE›
flex_l = 14; flex_w = 9;                // living-hinge tab size (print-tune)

/* ---------------- derived ------------------------------------------------- */
iw = bw + 2*tol;                        // inner cavity
id = bd + 2*tol;
ow = iw + 2*wall;                       // outer shell (without channel)
od = id + 2*wall;
inner_h = boss_h + bt + stack_h + top_air;
base_h  = floor_t + inner_h;            // open-top base height
ant_z   = floor_t + boss_h + bt + 9;    // channel/jack axis height (≈ socket top) ‹MEASURE›
bx0 = wall + tol;                       // board origin (SW hole ref) in shell coords
by0 = wall + tol;

$fn = $preview ? 24 : 48;

module m2_boss(x, y) {
    difference() {
        cylinder(d = 7, h = boss_h);
        translate([0,0,-1]) cylinder(d = 1.8, h = boss_h + 2);   // M2 self-tap
    }
    translate([x,y,0]) children();
}

module base() {
    difference() {
        union() {
            // main tub
            cube([ow, od, base_h]);
            // antenna guard: outer rail + floor bridge along the FULL north wall
            translate([0, od, 0])
                difference() {
                    cube([ow, ch_w + ch_wall, base_h]);            // solid wing
                    // trough the antenna lies in (open top for threading/RF)
                    translate([-1, 0.01, ant_z - ch_w/2])
                        cube([ow + 2, ch_w, base_h]);              // open-topped
                }
        }
        // cavity
        translate([wall, wall, floor_t]) cube([iw, id, base_h]);
        // LEMO hole, east wall (south half — clear of J1's harness line)
        translate([ow + 1, wall + 11, lemo_z])
            rotate([0, -90, 0]) cylinder(d = lemo_hole, h = wall + 2);
        // USB-C slot, east wall at Heltec module height
        translate([ow - wall - 1, od/2 - usb_w/2, floor_t + boss_h + bt + 11.5])
            cube([wall + 2, usb_w, usb_h]);
        // pigtail pass: slot from case interior into the NW pocket void
        translate([wall + 2, od - wall - 1, ant_z - 4]) cube([8, wall + 2, 8]);
    }
    // 4x M2 bosses (board's SW hole at (hole_in, hole_in) in board coords)
    for (p = [[hole_in, hole_in], [bw - hole_in, hole_in],
              [hole_in, bd - hole_in], [bw - hole_in, bd - hole_in]])
        translate([bx0 + p[0], by0 + p[1], floor_t]) m2_boss(0,0);
    // NW pocket: jack plate at the WEST end of the channel, hole axis EAST
    translate([0, od, 0]) difference() {
        cube([pocket_l, ch_w + ch_wall, ant_z + ch_w/2 + 2]);
        // SMA bulkhead hole through the pocket's east face (plate at x 8..14,
        // so barrel+50mm whip spans ~16..66 — inside the 67.8mm shell)
        translate([pocket_l - 6, ch_w/2, ant_z])
            rotate([0, 90, 0]) cylinder(d = sma_hole, h = 8);
        // pocket void (nut + pigtail room), opens west/into the pass slot
        translate([2, 2, ant_z - 6]) cube([pocket_l - 8, ch_w - 2, 12]);
    }
}

module lid() {
    difference() {
        union() {
            cube([ow, od, lid_t]);
            translate([wall/2, wall/2, -lip_h])                     // skirt
                difference() {
                    cube([ow - wall, od - wall, lip_h]);
                    translate([wall/2 + 0.3, wall/2 + 0.3, -1])
                        cube([ow - 2*wall - 0.6, od - 2*wall - 0.6, lip_h + 2]);
                }
        }
        // OLED window over the Heltec (module centred x 5.5..55.7, y 6.7..32.2
        // in board coords — window biased to module centre)
        translate([bx0 + 30 - oled_w/2, by0 + 22 - oled_d/2, -1])
            cube([oled_w, oled_d, lid_t + 2]);
        // two flexure button tabs (U-slots), south half — positions free by design
        for (fx = [18, 36])
            translate([fx, by0 + 8, -1]) difference() {
                cube([flex_l + 4, flex_w + 4, lid_t + 2]);
                translate([2, 2, -1]) cube([flex_l, flex_w, lid_t + 4]);
            }
    }
    // press bosses under the tabs (touch wired tact switches below)
    for (fx = [18, 36])
        translate([fx + 2 + flex_l/2, by0 + 10 + flex_w/2, -3]) cylinder(d = 4, h = 3);
}

// ghost antenna for the assembly view
module antenna_ghost() {
    color("black", 0.6)
        translate([pocket_l - 6 + sma_barrel, od + ch_w/2, ant_z])
            rotate([0, 90, 0]) cylinder(d = ant_d, h = ant_len);
}

if (part == "base") base();
if (part == "lid") lid();
if (part == "assembly") {
    base();
    color("steelblue", 0.5) translate([0, 0, base_h + lip_h + 3]) lid();
    antenna_ghost();
    // ghost board + heltec volume
    color("green", 0.4) translate([bx0, by0, floor_t + boss_h]) cube([bw, bd, bt]);
    color("orange", 0.3)
        translate([bx0 + 5.5, by0 + 6.7, floor_t + boss_h + bt + 11])
            cube([50.2, 25.5, 4.5]);
}
