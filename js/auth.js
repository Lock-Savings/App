// Lock Cash auth + data layer on Supabase (free tier). Phone number + password, stored in Supabase Auth.
(() => {
  'use strict';
  const cfg = window.LOCKCASH_CONFIG || {};
  const configured = !!(cfg.url && cfg.anonKey && !/YOUR-/.test(cfg.url + cfg.anonKey));
  const sb = configured && window.supabase ? window.supabase.createClient(cfg.url, cfg.anonKey) : null;
  const NOT_READY = 'The app is not connected to Supabase yet. Fill in js/config.js.';
  const toEmail = (p) => p.replace('+', '') + '@' + (cfg.emailDomain || 'lockcash.app');

  // 0712 345 678 / +254712345678 / 712345678 -> +254712345678
  function normPhone(raw) {
    let p = String(raw).replace(/[\s\-()]/g, '');
    if (p.startsWith('+')) p = p.slice(1);
    if (/^0[17]\d{8}$/.test(p)) p = '254' + p.slice(1);
    else if (/^[17]\d{8}$/.test(p)) p = '254' + p;
    return /^254[17]\d{8}$/.test(p) ? '+' + p : null;
  }
  function friendly(m) {
    if (/already registered|already been registered/i.test(m)) return 'That number already has an account. Please log in.';
    if (/invalid login/i.test(m)) return 'Wrong phone number or password.';
    if (/not confirmed/i.test(m)) return 'Email confirmation is on in Supabase. Turn off "Confirm email" (Authentication > Providers > Email).';
    if (/rate limit|too many/i.test(m)) return 'Too many attempts. Please wait a few minutes and try again.';
    if (/email.*invalid|invalid.*email/i.test(m)) return 'Supabase rejected the generated email. Change emailDomain in js/config.js.';
    if (/failed to fetch|network/i.test(m)) return 'Cannot reach the server. Check your internet connection.';
    return m;
  }

  const Auth = {
    async current() {
      if (!sb) return null;
      const { data } = await sb.auth.getSession();
      const u = data && data.session && data.session.user;
      return u ? { id: u.id, phone: (u.user_metadata && u.user_metadata.phone) || '', name: (u.user_metadata && u.user_metadata.name) || '' } : null;
    },
    async requireLogin() { const u = await Auth.current(); if (!u) { location.replace('login.html'); return null; } return u; },
    async logOut() { try { if (sb) await sb.auth.signOut(); } catch (e) { /* ignore */ } location.replace('login.html'); },

    async signUp({ name, phone, password, confirm }) {
      if (!sb) return { error: NOT_READY };
      const p = normPhone(phone);
      if (!p) return { error: 'Enter a valid Kenyan phone number, e.g. 0712 345 678.' };
      if (password.length < 8 || password.length > 64) return { error: 'Password must be 8 to 64 characters.' };
      if (password !== confirm) return { error: 'The two passwords do not match.' };
      const { data, error } = await sb.auth.signUp({ email: toEmail(p), password, options: { data: { name: name.trim().slice(0, 40), phone: p } } });
      if (error) return { error: friendly(error.message) };
      if (!data.session) return { error: 'Account created, but Supabase is asking for email confirmation. Turn off "Confirm email" in Supabase, then log in.' };
      return { ok: true };
    },
    async logIn({ phone, password }) {
      if (!sb) return { error: NOT_READY };
      const p = normPhone(phone);
      if (!p) return { error: 'Enter a valid Kenyan phone number, e.g. 0712 345 678.' };
      const { error } = await sb.auth.signInWithPassword({ email: toEmail(p), password });
      return error ? { error: friendly(error.message) } : { ok: true };
    },

    // ---- savings (row-level security: each user only ever sees their own rows) ----
    async loadSavings() {
      const { data, error } = await sb.from('savings').select('id,amount,code,due,saved_at,withdrawn_at').order('saved_at', { ascending: true });
      if (error) throw new Error(friendly(error.message));
      return data.map((r) => ({ id: r.id, saved: r.saved_at, amount: r.amount, code: r.code, due: r.due, withdrawn: r.withdrawn_at }));
    },
    async addSaving({ amount, code, due }) {
      const { error } = await sb.from('savings').insert({ amount, code, due });
      if (!error) return {};
      return { error: error.code === '23505' ? 'That M-Pesa code has already been saved.' : friendly(error.message) };
    },
    async withdrawAll() {
      const { data, error } = await sb.rpc('withdraw_all');
      return error ? { error: friendly(error.message) } : { total: data };
    }
  };
  window.LockCash = Auth;

  // ---- wire up whichever auth form is on the page ----
  async function wire(id, action) {
    const form = document.getElementById(id); if (!form) return;
    const err = document.getElementById('form-error'), btn = form.querySelector('button[type=submit]');
    if (!sb) { err.textContent = NOT_READY; err.hidden = false; }
    else if (await Auth.current()) { location.replace('home.html'); return; }
    const pws = form.querySelectorAll('[data-pw]'), show = document.getElementById('show-pw');
    if (show) show.addEventListener('change', () => pws.forEach((i) => { i.type = show.checked ? 'text' : 'password'; }));
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      err.hidden = true; btn.disabled = true;
      let res;
      try { res = await action(Object.fromEntries(new FormData(form))); } catch (ex) { res = { error: friendly(ex.message || 'Something went wrong.') }; }
      btn.disabled = false;
      if (res.ok) { location.replace('home.html'); return; }
      err.textContent = res.error; err.hidden = false; err.focus();
    });
  }
  document.addEventListener('DOMContentLoaded', () => { wire('signup-form', Auth.signUp); wire('login-form', Auth.logIn); });
})();
