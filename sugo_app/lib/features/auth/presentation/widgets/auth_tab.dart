/// Which auth form the screen is showing.
///
/// Named "tab" for history: the two forms used to sit under a segmented tab
/// switcher. Since 2026-09-28 the screen follows the reference design instead
/// - one form at a time, with "Don't have an account? Register" and "Already
/// have an account? Log in" underneath to move between them.
enum AuthTab { login, register }
