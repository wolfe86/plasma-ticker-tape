// The one web profile every TradingView window shares (TradingViewView.qml):
// its cookies, so a sign-in lasts, kept under
// ~/.local/share/plasmashell/QtWebEngine/plasma-ticker-tape. One object for
// the whole widget: two profiles with the same storage name cannot both open
// it, and the second window stayed blank (2026-10-25). Loaded by
// Workspace.qml through a Loader, so a system without Qt WebEngine still
// loads the widget.

import QtWebEngine

WebEngineProfile {
    storageName: "plasma-ticker-tape"
    offTheRecord: false
    persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
}
