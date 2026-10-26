-- @Test Ship/Wave|Test
-- Geometry Dash level 9: rows bottom (ground) to top, tiles see GDASH/phys.lua
-- u = seconds per music unit, m = looping tune: note+octave+length, R<n> = rest
-- rows are run-length coded: c*N = char c repeated byte(N)-32 times
return {
".**S.*'#.*/#.*'#.*-W.*&#.*+#.*%#.**m.*$#.*'#...#.*&n.C.*'^.*'^^.*.",
".*2#.*/#.*'#.*4#.*+#.*%#.*/#.*'#",
".*2#.*7#.*'#.*,#.*1#.*%#.*)#...#...#",
".*:#.*/#.*'#.*2#.*+#.*%#.*)#...#.*'#",
".*:#.*7#.*2#.*%#.*+#.*-#.*'#",
".*:#.*'#.*/#.*2#.*%#.*+#.*-#...#...#",
u = 0.1,
m = "C42 E42 G42 C52 B42 G42 E42 D42 A32 C42 E42 A42 G42 E42 C42 B32"
}
