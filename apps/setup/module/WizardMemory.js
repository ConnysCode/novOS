.pragma library

// What one page of the wizard leaves to the next: every page builds its own dialog, and
// the next one starts at the size the last one had, so that the card glides between them.
var lastCardHeight = 0;

function remember(height) {
    lastCardHeight = height;
}

function last() {
    return lastCardHeight;
}
