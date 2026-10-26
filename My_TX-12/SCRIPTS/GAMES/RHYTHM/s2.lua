-- Ode to Joy (Beethoven, 9th symphony). EASY
-- token: note+octave+length[mark]; length in units of u seconds
-- mark: none = tap, h = hold, s = slider, x = music only; R<n> = rest
return { u = 0.25, a = 1.5, m =
 "E52 E52 F52 G52 G52 F52 E52 D52 C52 C52 D52 E52 E53 D51x D54h " ..
 "E52 E52 F52 G52 G52 F52 E52 D52 C52 C52 D52 E52 D53 C51x C54h " ..
 "D52 D52 E52 C52 D52 E51x F51x E52 C52 D52 E51x F51x E52 D52 C52 D52 G44s " ..
 "E52 E52 F52 G52 G52 F52 E52 D52 C52 C52 D52 E52 D53 C51x C54h" }
