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

## Withdrawal email notifications (free)

The form records requests in Supabase. To email the administrator after each request without exposing an email credential in the website, use a Supabase Database Webhook and Google Apps Script. The email is sent from the Google account that owns the script. Apps Script quotas apply and can change; a consumer Gmail account currently has a limit of 100 email recipients per day.

1. Sign in to [Google Apps Script](https://script.google.com/) as the account that should send the email. Create a project and replace `Code.gs` with the contents of `google-apps-script/Code.gs` in this repository.
2. In **Project Settings > Script properties**, add `WEBHOOK_SECRET` with a long random value and `ADMIN_EMAIL` with `vanywinner@gmail.com`. Keep the secret private; do not put it in this repository or the website.
3. Choose **Deploy > New deployment > Web app**. Set **Execute as** to your account and **Who has access** to **Anyone**, then deploy and authorize the requested email permission. Keep the deployed URL private because it is an endpoint protected by the secret.
4. In Supabase **Database > Webhooks**, create an `INSERT` webhook for `public.withdrawal_requests`, method `POST`, using the deployed Apps Script URL with `?key=` followed by the same secret. Do not add a trailing slash after `/exec` before the query string.
5. Submit a test withdrawal request and check the admin inbox and the Apps Script **Executions** page. The webhook runs after the database insert; email delivery is asynchronous. A recorded request remains valid even if email delivery fails.

The website does not send email directly. If the webhook secret is exposed, replace it in Apps Script properties and update the Supabase webhook URL.
