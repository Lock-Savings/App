# Lock Cash (practice project)
Static savings-lock app. No server, no paid services. Data lives in the browser (localStorage).

Run locally: `python3 -m http.server 8000` then open http://localhost:8000
Host free: GitHub Pages (Settings > Pages > deploy from main branch).

Edit `POCHI_NUMBER` / `POCHI_NAME` at the top of the script in home.html.
Limits: accounts and savings are per-browser and M-Pesa codes are not verified. A real version needs a backend.
