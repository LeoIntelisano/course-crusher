# Connect a Google Calendar using a private iCal link

For the JacHammer preview (where OAuth callback URLs can change), students can
connect a Google Calendar **without OAuth**:

1. On a computer, open Google Calendar → Settings.
2. Under **Settings for my calendars**, choose a calendar.
3. Under **Integrate calendar**, copy **Secret address in iCal format**.
4. In CourseCrusher → Connections → **Calendar via iCal link**, paste that link
   and click **Save iCal calendar**.
5. CourseCrusher reads events into the calendar and avoids busy times. Use
   **Refresh events** to load newer data, or **Disconnect iCal** to forget the link.

The link acts as a password for reading that calendar. Never put it in GitHub,
logs, screenshots, or public documentation. CourseCrusher stores it with the
signed-in student's data; the backend fetches it on demand (5-minute cache).
No credentials or redirect URI are needed for the iCal option. Students may
also use Google OAuth separately if the server has a stable callback URL.

Limitations: Read-only; Google may delay iCal feed updates; some school accounts
hide secret iCal links; each saved link covers one calendar; recurring meetings
are expanded, and all-day entries are displayed but do not reserve every hour.
This initial implementation accepts only Google's HTTPS iCal URL format to
avoid fetching arbitrary internal URLs from the hosting server. Calendar URLs
are limited to 2,048 characters and feeds to 2 MB per fetch.

## Verify

Run `jac check web.jac`, `jac test suite.jac`, and
`python -m unittest discover -s tests -p 'test_ical_feed.py'`.

Then test with two different student accounts, and verify that the URL and
events do not cross accounts. On the JacHammer preview, verify that a class
from the imported calendar blocks a proposed study time. Refresh, reload,
and disconnect to test the full flow.
