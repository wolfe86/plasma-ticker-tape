"""
A ticker's recent Finviz headlines, the company's own news ranked first.
"""

import sys

def recent_news(ticker, name="", limit=3):
    """
    Newest Finviz headlines for a ticker, company news first.

    > A ticker's Finviz page also carries commentary that merely *mentions* it.
    > Taken newest-first, ADBE's top headline was about Autodesk and CRM's about
    > Microsoft -- shown as "the catalyst" that is simply wrong. Wire-service
    > releases (the company's own announcements) are ranked first, then
    > headlines naming the company or ticker, then the rest.
    """
    try:
        import premarket_report as pm
        rows = pm.get_finviz(ticker).get("news")
    except Exception as e:
        print(f"  ! news lookup failed: {e}", file=sys.stderr)
        return []
    if not rows:
        return []

    word = (name or "").split(",")[0].split()[0].lower() if name else ""
    tick = ticker.lower()

    def rank(n):
        src = (n.get("source") or "").lower()
        title = (n.get("title") or "").lower()
        if any(w in src for w in pm.PR_WIRES):
            return 0                      # the company's own announcement
        if word and word in title:
            return 1                      # names the company
        if tick in title.split():
            return 1
        return 2                          # commentary that merely mentions it

    rows = sorted(rows, key=lambda n: (rank(n), -n["dt"].timestamp()))
    for n in rows:
        n["is_company_news"] = rank(n) < 2
    return rows[:limit]
