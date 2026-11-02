# Lock Cash (practice project)
Static front end on GitHub Pages + free Supabase backend (auth + Postgres). Data syncs across devices.

## Setup (once)
1. supabase.com > New project (free, no card).
2. SQL Editor > paste `supabase/setup.sql` > Run.
3. Authentication > Providers > Email: turn OFF "Confirm email".
4. Project Settings > API: copy the Project URL and the anon (or publishable) key into `js/config.js`.
5. Push to GitHub; Settings > Pages > deploy from `main` / root.

Never put the service_role key in this repo. Edit POCHI_NUMBER / POCHI_NAME in home.html.
Limits: M-Pesa codes are format-checked only, and withdrawals are recorded but not actually paid out.
