-- =========================================================
-- Finansial OS — Migration awal
-- Tabel: profiles (status premium user) & orders (transaksi Midtrans)
-- =========================================================

-- 1. Tabel profil tambahan untuk tiap user auth.users
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  is_premium boolean not null default false,
  premium_since timestamptz,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- User hanya bisa baca profilnya sendiri
create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

-- Tidak ada insert/update langsung dari client; semua lewat trigger & edge function (service role)
-- (service role bypass RLS secara default)

-- 2. Trigger: setiap kali user baru daftar di auth.users, otomatis buat row profiles
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 3. Tabel orders — mencatat setiap transaksi Midtrans
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_id text not null unique,              -- order_id yang dikirim ke Midtrans (harus unik)
  user_id uuid references auth.users(id) on delete set null,
  email text not null,
  gross_amount numeric not null,
  status text not null default 'pending',      -- pending | paid | failed | expired | cancelled
  payment_type text,
  midtrans_transaction_id text,
  raw_notification jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.orders enable row level security;

-- User hanya bisa lihat order miliknya sendiri (berdasarkan user_id ATAU email saat belum login)
create policy "orders_select_own"
  on public.orders for select
  using (auth.uid() = user_id);

-- Insert/update orders hanya lewat Edge Function (service role), client tidak boleh insert langsung
-- supaya status pembayaran tidak bisa dipalsukan dari browser.

create index if not exists idx_orders_order_id on public.orders(order_id);
create index if not exists idx_orders_email on public.orders(email);
create index if not exists idx_orders_user_id on public.orders(user_id);

-- 4. Function bantu: set premium = true untuk user tertentu (dipanggil dari webhook via service role)
create or replace function public.mark_user_premium(target_email text, target_user_id uuid default null)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if target_user_id is not null then
    update public.profiles
      set is_premium = true, premium_since = now()
      where id = target_user_id;
  else
    update public.profiles
      set is_premium = true, premium_since = now()
      where email = target_email;
  end if;
end;
$$;

-- 5. updated_at auto-update trigger untuk orders
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_orders_updated_at on public.orders;
create trigger trg_orders_updated_at
  before update on public.orders
  for each row execute procedure public.set_updated_at();
