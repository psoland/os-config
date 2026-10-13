// The grid renderer only needs OpenTUI's border glyphs and italic flag.
// Keep its native terminal renderer out of the Neovim helper entirely.
// Values match @opentui/core 0.5.8 (MIT).
const single = {
  topLeft: "┌",
  topRight: "┐",
  bottomLeft: "└",
  bottomRight: "┘",
  horizontal: "─",
  vertical: "│",
  topT: "┬",
  bottomT: "┴",
  leftT: "├",
  rightT: "┤",
  cross: "┼",
};
export const BorderChars = {
  single,
  rounded: {
    ...single,
    topLeft: "╭",
    topRight: "╮",
    bottomLeft: "╰",
    bottomRight: "╯",
  },
  double: {
    topLeft: "╔",
    topRight: "╗",
    bottomLeft: "╚",
    bottomRight: "╝",
    horizontal: "═",
    vertical: "║",
    topT: "╦",
    bottomT: "╩",
    leftT: "╠",
    rightT: "╣",
    cross: "╬",
  },
  heavy: {
    topLeft: "┏",
    topRight: "┓",
    bottomLeft: "┗",
    bottomRight: "┛",
    horizontal: "━",
    vertical: "┃",
    topT: "┳",
    bottomT: "┻",
    leftT: "┣",
    rightT: "┫",
    cross: "╋",
  },
};
export const TextAttributes = { ITALIC: 1 << 2 };

// Upstream style modules also import these, but their OpenTUI text/color
// functions are tree-shaken out: we serialize semantic grid styles instead.
// Fail loudly if a future source update accidentally uses that UI path.
export class RGBA {
  constructor() {
    throw new Error("OpenTUI colors are not used by the Neovim adapter");
  }
}
export class StyledText {
  constructor() {
    throw new Error("OpenTUI text is not used by the Neovim adapter");
  }
}
