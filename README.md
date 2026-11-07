# Lock Cash (practice project)

Static front end on GitHub Pages + free Supabase backend (auth + Postgres). Data syncs across devices.

## Setup

1. Create a Supabase project on its free plan.
2. Before applying `supabase/setup.sql` to an existing project, export a database backup. The script is additive and does not drop application tables or rows, but it changes policies, functions, and withdrawal-request permissions.
3. In Supabase SQL Editor, run the complete `supabase/setup.sql` script. Check that the transaction completes successfully before deploying the matching app files.
4. Authentication > Providers > Email: turn OFF "Confirm email".
5. Project Settings > API: copy the Project URL and the anon (or publishable) key into `js/config.js`.
6. Push to GitHub; Settings > Pages > deploy from `main` / root.

Never put the service_role key in this repo. Edit POCHI_NUMBER / POCHI_NAME in home.html.
M-Pesa codes are format-checked only; payment verification is manual. Withdrawal requests are checked by the database: all active payments must be verified, full withdrawals require all savings to mature, and partial withdrawals are limited to 70% of remaining matured verified savings. An administrator can approve a request after 72 hours, then must send the M-Pesa payout separately and record its confirmation code in the admin dashboard. Approval does not send money automatically.

The administrator is the allowlisted email in `supabase/setup.sql` or a user whose `is_admin` flag is set in Supabase `app_metadata` by a trusted administrator. Do not set admin privileges through user-editable metadata or the browser.
