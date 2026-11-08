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

// The same for lists that scroll by whole entries, for example the search hits.
function centredIndex(index, visible, count) {
    return Math.round(centred(index, 1, visible, count));
}
