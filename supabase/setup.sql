-- Lock Cash: run this once in Supabase > SQL Editor > New query > Run.
-- Safe to re-run: it drops and recreates the objects below (this DELETES saved rows).

drop function if exists public.withdraw_all();
drop table if exists public.savings;

create table public.savings (
  id          bigint generated always as identity primary key,
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  amount      integer not null check (amount between 1 and 250000),
  code        text not null unique check (code ~ '^[A-Z0-9]{10}$'),
  due         date not null,
  saved_at    timestamptz not null default now(),
  withdrawn_at timestamptz
);
create index savings_user_idx on public.savings (user_id);

alter table public.savings enable row level security;

-- Users can only read and add their own rows. No update/delete policy exists,
-- so the browser can never edit or remove a record; withdrawals go through withdraw_all().
create policy "read own savings" on public.savings
  for select to authenticated using (user_id = auth.uid());
create policy "add own savings" on public.savings
  for insert to authenticated with check (user_id = auth.uid() and withdrawn_at is null);

-- Server-side rules for every new saving (cannot be bypassed from the browser).
create or replace function public.check_new_saving() returns trigger
language plpgsql set search_path = public as $$
declare
  today  date := (now() at time zone 'Africa/Nairobi')::date;
  locked date;
begin
  if new.due <= today then
    raise exception 'The due date must be tomorrow or later.';
  end if;
  select max(due) into locked from public.savings
    where user_id = new.user_id and withdrawn_at is null;
  if locked is not null and new.due < locked then
    raise exception 'Your savings are already locked until %. Choose that date or later.', locked;
  end if;
  new.saved_at := now();
  return new;
end $$;

create trigger check_new_saving before insert on public.savings
  for each row execute function public.check_new_saving();

-- Withdraw everything, only once the latest due date has arrived (Nairobi time).
create or replace function public.withdraw_all() returns integer
language plpgsql security definer set search_path = public as $$
declare
  today  date := (now() at time zone 'Africa/Nairobi')::date;
  locked date;
  total  integer;
begin
  select max(due), coalesce(sum(amount), 0) into locked, total
    from public.savings where user_id = auth.uid() and withdrawn_at is null;
  if locked is null then raise exception 'You have no savings to withdraw.'; end if;
  if locked > today then raise exception 'Your savings have not matured yet.'; end if;
  update public.savings set withdrawn_at = now()
    where user_id = auth.uid() and withdrawn_at is null;
  return total;
end $$;

revoke all on function public.withdraw_all() from public, anon;
grant execute on function public.withdraw_all() to authenticated;
