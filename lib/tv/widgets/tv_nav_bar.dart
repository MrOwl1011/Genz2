/// The persistent content sections reachable from the left navigation rail
/// (see `tv_sidebar.dart`'s `TvSidebar`) that have an actual lingering
/// "you are here" body — Live is a pushed full-screen route rather than an
/// inline body swap like Movies/Series, but it still counts as one of
/// these for highlighting purposes (see TvSidebar's `active` param).
///
/// Search and Settings are one-shot actions with no persistent section of
/// their own, so they're deliberately not members of this enum — see
/// TvSidebarItem in tv_sidebar.dart for the full five-item navigation list.
enum TvSection { live, movies, series }
