.pragma library

// Scrolling of every novOS list (docs/design-system.md, "Lange Listen"): the focused
// entry stays in the middle of the visible part until the list reaches its start or end.
// The settings modal, the panel's apps and languages, the Wi-Fi list, the search hits, the
// source picker and the Smart Home tiles all scroll with this one rule.
//
// start and size: the focused entry along the list; view: the visible length; content:
// the whole list including its end gap. All in the same unit. Returns the scroll offset.
function centred(start, size, view, content) {
    var limit = Math.max(0, content - view);
    return Math.max(0, Math.min(start + size / 2 - view / 2, limit));
}

// The same for lists whose first or last focusable entry is not their first or last element:
// a head block, section titles or rows that only show a value lie before or after it. If they
// reach past the middle, centred alone never shows the list's start or end again, and Up
// stops with the start still hidden. first and last are { start, size } of the first and the
// last entry that take the focus. The first then shows the list's start, the last its end, as
// far as the entry itself stays in view; in between the offset leans that way step by step,
// so the focus keeps moving the way of the key. Lists without such elements scroll exactly
// as with centred.
function centredBetween(start, size, view, content, first, last) {
    var offset = centred(start, size, view, content);
    var limit = Math.max(0, content - view);
    var lowest = Math.max(0, Math.min(first.start + first.size - view, limit));
    var highest = Math.min(limit, Math.max(0, last.start));
    var topExcess = Math.max(0, centred(first.start, first.size, view, content) - lowest);
    var endShortfall = Math.max(0, highest - centred(last.start, last.size, view, content));
    if (topExcess === 0 && endShortfall === 0) return offset;
    var firstMiddle = first.start + first.size / 2;
    var span = last.start + last.size / 2 - firstMiddle;
    var towardsEnd = span > 0 ? Math.max(0, Math.min((start + size / 2 - firstMiddle) / span, 1)) : 0;
    return Math.max(0, Math.min(offset - topExcess * (1 - towardsEnd) + endShortfall * towardsEnd, limit));
}

// The same for lists that scroll by whole entries, for example the search hits.
function centredIndex(index, visible, count) {
    return Math.round(centred(index, 1, visible, count));
}
