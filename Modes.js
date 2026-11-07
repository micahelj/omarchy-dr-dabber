.pragma library

// Switch 2 LED modes: name per mode byte (decoded from the Dr.Dabber app) and 2-3 representative colors
// sampled from the app's mode renders. 18-23 are unused. Calm turns the LED strip off but leaves the button light on (confirmed on device); Stealth turns off everything including the button light (confirmed on device).
var modes = [
  { n: 0,  name: "Stealth",          group: "off",   colors: [], hint: "all lights off" },
  { n: 1,  name: "Calm",             group: "off",   colors: [], hint: "strip off" },
  { n: 2,  name: "Purple",           group: "solid", colors: ["#5700a3", "#7b0bd3"] },
  { n: 3,  name: "Blue",             group: "solid", colors: ["#0a37a8", "#1163ea"] },
  { n: 4,  name: "Cyan",             group: "solid", colors: ["#0caba7", "#23fcea"] },
  { n: 5,  name: "Green",            group: "solid", colors: ["#0e831d", "#16d318"] },
  { n: 6,  name: "Yellow",           group: "solid", colors: ["#b7c007", "#f6fe16"] },
  { n: 7,  name: "Orange",           group: "solid", colors: ["#af4f04", "#f26d28"] },
  { n: 8,  name: "Red",              group: "solid", colors: ["#720814", "#cc000a"] },
  { n: 9,  name: "Pink",             group: "solid", colors: ["#bd00c8", "#e709f2"] },
  { n: 10, name: "Cali Sunset",      group: "theme", colors: ["#670371", "#be3570", "#ef9a66"] },
  { n: 11, name: "Purple Haze",      group: "theme", colors: ["#5700af", "#a042f6"] },
  { n: 12, name: "Northern Lights",  group: "theme", colors: ["#60549f", "#5ce7d5", "#8bff8e"] },
  { n: 13, name: "Vegas Nights",     group: "theme", colors: ["#be16ed", "#5ca2ec", "#9e51f6"] },
  { n: 14, name: "Blue Dream",       group: "theme", colors: ["#0b3b92", "#3f8ae4", "#64baf5"] },
  { n: 15, name: "Strawberry Cough", group: "theme", colors: ["#c80015", "#e1038f", "#f12bbd"] },
  { n: 16, name: "Florida Groves",   group: "theme", colors: ["#ca8506", "#f9e019", "#fefc73"] },
  { n: 17, name: "Lime Light",       group: "theme", colors: ["#7aff0a", "#d9ff1a", "#f0ff63"] },
  { n: 24, name: "Blue Cheese",      group: "theme", colors: ["#074ee4", "#2a9ed8", "#f5cc29"] },
  { n: 25, name: "Golden Goat",      group: "theme", colors: ["#ee9c0b", "#fd6d01", "#bbcc36"] },
  { n: 26, name: "Grape Ape",        group: "theme", colors: ["#5e0fe9", "#7d00fe", "#1fe929"] },
  { n: 27, name: "Miami Vice",       group: "theme", colors: ["#672df4", "#4089f2", "#09daf1"] },
  { n: 28, name: "Purple Urkle",     group: "theme", colors: ["#c102f8", "#7001ec", "#fdcb49"] }
]

function byNumber(n) {
  for (var i = 0; i < modes.length; i++) if (modes[i].n === n) return modes[i]
  return null
}
function byName(name) {
  for (var i = 0; i < modes.length; i++) if (modes[i].name === name) return modes[i]
  return null
}
function inGroup(group) {
  return modes.filter(function(m) { return m.group === group })
}
// Next/previous valid mode number, wrapping. dir = +1 / -1.
function step(n, dir) {
  var idx = -1
  for (var i = 0; i < modes.length; i++) if (modes[i].n === n) idx = i
  if (idx < 0) return modes[0].n
  return modes[(idx + dir + modes.length) % modes.length].n
}
// Perceived brightness 0..1 of a "#rrggbb" color, to pick readable label text.
function luminance(hex) {
  var r = parseInt(hex.substr(1, 2), 16) / 255, g = parseInt(hex.substr(3, 2), 16) / 255, b = parseInt(hex.substr(5, 2), 16) / 255
  return 0.299 * r + 0.587 * g + 0.114 * b
}
