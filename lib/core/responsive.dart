/// Shared sizing rules for poster/card grids.
///
/// These screens are shown on phones, tablets and TVs from the same code, so
/// a fixed column count can't work: a count tuned for a ~400dp phone stretches
/// each poster across a third of a TV screen, while a count tuned for a TV
/// leaves phone posters unreadably small.
library;

/// Number of columns for a poster grid at [maxWidth] logical pixels.
///
/// Targets a ~130dp poster, which keeps roughly the phone's existing 3-up
/// layout while giving a typical 960dp-wide TV surface 7 columns instead of 3.
/// Clamped so a very narrow window never drops below 3 and a very wide one
/// doesn't degenerate into a wall of thumbnails.
int posterGridColumns(double maxWidth) => (maxWidth / 130).round().clamp(3, 8);

/// Pixel width to decode a poster image at, for a grid of [columns] across
/// [maxWidth].
///
/// Without this, `CachedNetworkImage` decodes at the image's full source
/// resolution — IPTV poster art is routinely 1000×1500 or larger — and holds
/// every visible one in memory at that size. On the low-RAM Android TV boxes
/// this app targets (many ship with under 2GB) that is the single biggest
/// cause of scroll jank and out-of-memory image churn, since a screenful of
/// posters can otherwise pin hundreds of megabytes. Decoding at display size
/// costs nothing visually and cuts that by more than an order of magnitude.
///
/// The 2x factor keeps posters crisp on high-density panels.
int posterDecodeWidth(double maxWidth, int columns) =>
    ((maxWidth / columns) * 2).round().clamp(180, 600);
