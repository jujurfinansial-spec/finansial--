-- =========================================================
-- Finansial OS — Migration data finansial user
-- Menyimpan snapshot data (gaji, anggaran, dana darurat, dll)
-- per user sebagai JSONB, mengganti localStorage agar sinkron antar device.
-- =========================================================

create table if not exists public.financial_data (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.financial_data enable row level security;

-- User hanya boleh baca & tulis datanya sendiri
create policy "financial_data_select_own"
  on public.financial_data for select
  using (auth.uid() = user_id);

create policy "financial_data_insert_own"
  on public.financial_data for insert
  with check (auth.uid() = user_id);

create policy "financial_data_update_own"
  on public.financial_data for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop trigger if exists trg_financial_data_updated_at on public.financial_data;
create trigger trg_financial_data_updated_at
  before update on public.financial_data
  for each row execute procedure public.set_updated_at();
