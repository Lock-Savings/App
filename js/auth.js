// Lock Cash: demo-grade auth kept in this browser (localStorage). Practice only: replace with a real backend before real money.
(() => {
  'use strict';
  const USERS = 'lockcash.users.v1', SESSION = 'lockcash.session.v1';
  const read = (k, f) => { try { const v = JSON.parse(localStorage.getItem(k)); return v ?? f; } catch (e) { return f; } };
  const write = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); return true; } catch (e) { return false; } };
  const b64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)));
  const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

  // 0712 345 678 / +254712345678 / 712345678 -> +254712345678
  function normPhone(raw) {
    let p = String(raw).replace(/[\s\-()]/g, '');
    if (p.startsWith('+')) p = p.slice(1);
    if (/^0[17]\d{8}$/.test(p)) p = '254' + p.slice(1);
    else if (/^[17]\d{8}$/.test(p)) p = '254' + p;
    return /^254[17]\d{8}$/.test(p) ? '+' + p : null;
  }
  async function hash(pw, saltB64) {
    if (!(window.crypto && crypto.subtle)) throw new Error('Open this app over https or localhost so passwords can be protected.');
    const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(pw), 'PBKDF2', false, ['deriveBits']);
    return b64(await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: unb64(saltB64), iterations: 150000 }, key, 256));
  }

  const Auth = {
    current() { const phone = read(SESSION, null); const u = phone && read(USERS, {})[phone]; return u ? { phone: u.phone, name: u.name } : null; },
    logOut() { try { localStorage.removeItem(SESSION); } catch (e) {} location.replace('login.html'); },
    requireLogin() { const u = Auth.current(); if (!u) { location.replace('login.html'); return null; } return u; },
    async signUp({ name, phone, password, confirm }) {
      const p = normPhone(phone);
      if (!p) return { error: 'Enter a valid Kenyan phone number, e.g. 0712 345 678.' };
      if (password.length < 8 || password.length > 64) return { error: 'Password must be 8 to 64 characters.' };
      if (password !== confirm) return { error: 'The two passwords do not match.' };
      const users = read(USERS, {});
      if (users[p]) return { error: 'That number already has an account. Please log in.' };
      const salt = b64(crypto.getRandomValues(new Uint8Array(16)));
      users[p] = { phone: p, name: name.trim().slice(0, 40), salt, hash: await hash(password, salt) };
      if (!write(USERS, users) || !write(SESSION, p)) return { error: 'Your browser blocked storage, so the account could not be saved.' };
      return { ok: true };
    },
    async logIn({ phone, password }) {
      const p = normPhone(phone), u = p && read(USERS, {})[p];
      if (!u || (await hash(password, u.salt)) !== u.hash) return { error: 'Wrong phone number or password.' };
      write(SESSION, p);
      return { ok: true };
    }
  };
  window.LockCash = Auth;

  // ---- wire up whichever auth form is on the page ----
  const wire = (id, action) => {
    const form = document.getElementById(id); if (!form) return;
    if (Auth.current()) { location.replace('home.html'); return; }
    const err = document.getElementById('form-error'), btn = form.querySelector('button[type=submit]');
    const pws = form.querySelectorAll('[data-pw]');
    const show = document.getElementById('show-pw');
    if (show) show.addEventListener('change', () => pws.forEach((i) => { i.type = show.checked ? 'text' : 'password'; }));
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      err.hidden = true; btn.disabled = true;
      const data = Object.fromEntries(new FormData(form));
      let res;
      try { res = await action(data); } catch (ex) { res = { error: ex.message || 'Something went wrong.' }; }
      btn.disabled = false;
      if (res.ok) { location.replace('home.html'); return; }
      err.textContent = res.error; err.hidden = false; err.focus();
    });
  };
  document.addEventListener('DOMContentLoaded', () => { wire('signup-form', Auth.signUp); wire('login-form', Auth.logIn); });
})();
