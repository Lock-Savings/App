-- Lock Cash: safe to run on an existing database; no application rows are dropped.
begin;

create table if not exists public.savings (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  amount integer not null check (amount between 1 and 250000),
  code text not null unique check (code ~ '^[A-Z0-9]{10}$'),
  due date not null,
  saved_at timestamptz not null default now(),
  withdrawn_at timestamptz
);

-- Existing savings remain verified; new payments are explicitly inserted as pending.
alter table public.savings
  add column if not exists payment_status text not null default 'verified',
  add column if not exists verified_at timestamptz,
  add column if not exists verified_by uuid references auth.users(id),
  add column if not exists rejection_reason text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.savings'::regclass
      and conname = 'savings_payment_status_check'
  ) then
    alter table public.savings
      add constraint savings_payment_status_check
      check (payment_status in ('pending', 'verified', 'rejected')) not valid;
  end if;
end $$;

alter table public.savings validate constraint savings_payment_status_check;
create index if not exists savings_user_idx on public.savings (user_id);
alter table public.savings enable row level security;

create or replace function public.is_admin() returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1
    from auth.users
    where id = auth.uid()
      and (
        lower(coalesce(email, '')) = 'vanywinner@gmail.com'
        or raw_app_meta_data->>'is_admin' = 'true'
      )
  );
$$;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

create or replace function public.admin_list_users() returns table(id uuid, email text)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Administrator access required.';
  end if;

  return query
    select u.id, u.email
    from auth.users u
    order by u.email asc;
end;
$$;

revoke all on function public.admin_list_users() from public, anon;
grant execute on function public.admin_list_users() to authenticated;

drop policy if exists "read own savings" on public.savings;
drop policy if exists "add own savings" on public.savings;
drop policy if exists "admin can update savings" on public.savings;
create policy "read own savings" on public.savings
  for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "add own savings" on public.savings
  for insert to authenticated with check (user_id = auth.uid() and withdrawn_at is null);
create policy "admin can update savings" on public.savings
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

create or replace function public.check_new_saving() returns trigger
language plpgsql set search_path = public as $$
declare
  today date := (now() at time zone 'Africa/Nairobi')::date;
  locked date;
begin
  if new.due <= today then
    raise exception 'The due date must be tomorrow or later.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 0));

  select max(due) into locked
  from public.savings
  where user_id = new.user_id and withdrawn_at is null;

  if locked is not null and new.due < locked then
    raise exception 'Your savings are already locked until %. Choose that date or later.', locked;
  end if;

  new.saved_at := now();
  return new;
end;
$$;

drop trigger if exists check_new_saving on public.savings;
create trigger check_new_saving before insert on public.savings
  for each row execute function public.check_new_saving();

create table if not exists public.withdrawal_requests (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  request_type text not null check (request_type in ('full', 'partial')),
  amount integer not null check (amount > 0),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'paid')),
  created_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  paid_by uuid references auth.users(id),
  paid_at timestamptz,
  notes text
);

alter table public.withdrawal_requests
  add column if not exists paid_by uuid references auth.users(id),
  add column if not exists paid_at timestamptz;
alter table public.withdrawal_requests
  drop constraint if exists withdrawal_requests_status_check;
alter table public.withdrawal_requests
  add constraint withdrawal_requests_status_check
  check (status in ('pending', 'approved', 'rejected', 'paid')) not valid;
alter table public.withdrawal_requests
  validate constraint withdrawal_requests_status_check;

create index if not exists withdrawal_requests_user_idx on public.withdrawal_requests (user_id);
create index if not exists withdrawal_requests_status_idx on public.withdrawal_requests (status);
alter table public.withdrawal_requests enable row level security;

drop policy if exists "read own withdrawal requests" on public.withdrawal_requests;
drop policy if exists "add own withdrawal requests" on public.withdrawal_requests;
drop policy if exists "admin update withdrawal requests" on public.withdrawal_requests;
create policy "read own withdrawal requests" on public.withdrawal_requests
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

revoke all on public.withdrawal_requests from public, anon, authenticated;
grant select on public.withdrawal_requests to authenticated;

create or replace function public.admin_list_withdrawal_requests()
returns table(
  id bigint,
  user_id uuid,
  user_phone text,
  user_name text,
  request_type text,
  amount integer,
  status text,
  created_at timestamptz,
  reviewed_at timestamptz,
  paid_at timestamptz,
  notes text
)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Administrator access required.';
  end if;

  return query
    select wr.id,
           wr.user_id,
           coalesce(u.raw_user_meta_data->>'phone', u.phone, u.email, ''),
           coalesce(u.raw_user_meta_data->>'name', ''),
           wr.request_type,
           wr.amount,
           wr.status,
           wr.created_at,
           wr.reviewed_at,
           wr.paid_at,
           wr.notes
    from public.withdrawal_requests wr
    join auth.users u on u.id = wr.user_id
    order by wr.created_at desc;
end;
$$;

revoke all on function public.admin_list_withdrawal_requests() from public, anon;
grant execute on function public.admin_list_withdrawal_requests() to authenticated;

create or replace function public.request_withdrawal(
  p_request_type text,
  p_amount integer
) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid := auth.uid();
  v_today date := (now() at time zone 'Africa/Nairobi')::date;
  v_active_count integer;
  v_unverified_count integer;
  v_total bigint;
  v_matured_total bigint;
  v_paid_total bigint;
  v_partial_limit integer;
  v_request_amount integer;
  v_request_id bigint;
begin
  if v_user_id is null then
    raise exception 'Log in before requesting a withdrawal.';
  end if;
  if p_request_type is null or p_request_type not in ('full', 'partial') then
    raise exception 'Choose a full or partial withdrawal request.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text, 0));

  if exists (
    select 1 from public.withdrawal_requests
    where user_id = v_user_id and status in ('pending', 'approved')
  ) then
    raise exception 'You already have a withdrawal request awaiting completion.';
  end if;

  select count(*),
         count(*) filter (where payment_status <> 'verified'),
         coalesce(sum(amount), 0),
         coalesce(sum(amount) filter (where due <= v_today), 0)
    into v_active_count, v_unverified_count, v_total, v_matured_total
  from public.savings
  where user_id = v_user_id and withdrawn_at is null;

  select coalesce(sum(amount), 0) into v_paid_total
  from public.withdrawal_requests
  where user_id = v_user_id and status = 'paid';

  v_total := greatest(v_total - v_paid_total, 0);
  v_matured_total := greatest(v_matured_total - v_paid_total, 0);

  if v_active_count = 0 then
    raise exception 'You have no active savings to withdraw.';
  end if;
  if v_unverified_count > 0 then
    raise exception 'All active payments must be verified before requesting a withdrawal.';
  end if;

  if v_total = 0 then
    raise exception 'There is no remaining balance available for withdrawal.';
  end if;

  if p_request_type = 'full' then
    if exists (
      select 1 from public.savings
      where user_id = v_user_id and withdrawn_at is null and due > v_today
    ) then
      raise exception 'All savings must mature before requesting a full withdrawal.';
    end if;
    if v_total < 1 then
      raise exception 'There is no remaining balance available for withdrawal.';
    end if;
    v_request_amount := v_total::integer;
  else
    if p_amount is null or p_amount < 1 then
      raise exception 'Enter a positive whole-shilling amount.';
    end if;
    v_partial_limit := floor(v_matured_total * 0.70)::integer;
    if p_amount > v_partial_limit then
      raise exception 'Partial withdrawal limit is KES % (70%% of matured verified savings).', v_partial_limit;
    end if;
    v_request_amount := p_amount;
  end if;

  insert into public.withdrawal_requests (user_id, request_type, amount)
  values (v_user_id, p_request_type, v_request_amount)
  returning id into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function public.request_withdrawal(text, integer) from public, anon;
grant execute on function public.request_withdrawal(text, integer) to authenticated;

create or replace function public.review_withdrawal_request(
  p_request_id bigint,
  p_status text,
  p_notes text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_created_at timestamptz;
  v_locked_id bigint;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required.';
  end if;

  if p_status in ('approved', 'rejected') then
    select created_at into v_created_at
    from public.withdrawal_requests
    where id = p_request_id and status = 'pending'
    for update;

    if not found then
      raise exception 'This request does not exist or has already been reviewed.';
    end if;
    if p_status = 'approved' and v_created_at > now() - interval '72 hours' then
      raise exception 'A withdrawal request can only be approved after 72 hours.';
    end if;

    update public.withdrawal_requests
    set status = p_status,
        reviewed_by = auth.uid(),
        reviewed_at = now(),
        notes = coalesce(nullif(btrim(p_notes), ''), initcap(p_status) || ' by admin')
    where id = p_request_id;
  elsif p_status = 'paid' then
    select id into v_locked_id
    from public.withdrawal_requests
    where id = p_request_id and status = 'approved'
    for update;

    if not found then
      raise exception 'Only an approved request can be marked as paid.';
    end if;

    update public.withdrawal_requests
    set status = 'paid',
        paid_by = auth.uid(),
        paid_at = now(),
        notes = coalesce(nullif(btrim(p_notes), ''), 'Manual payout recorded by admin')
    where id = p_request_id;
  else
    raise exception 'Choose approved, rejected, or paid.';
  end if;
end;
$$;

revoke all on function public.review_withdrawal_request(bigint, text, text) from public, anon;
grant execute on function public.review_withdrawal_request(bigint, text, text) to authenticated;

-- Retire the old direct-withdrawal RPC; withdrawals now require an admin-reviewed request.
create or replace function public.withdraw_all() returns integer
language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Direct withdrawals are disabled. Submit a withdrawal request instead.';
end;
$$;

revoke all on function public.withdraw_all() from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;
