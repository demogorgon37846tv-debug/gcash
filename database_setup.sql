-- GCash Transaction Portal Database Setup
-- Run this SQL in your Supabase SQL Editor

-- 1) Create the profiles table (id references auth.users)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  -- full_name is populated from auth.metadata via signUp options.data.full_name
  full_name text,
  avatar_url text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 2) Create the transactions table
create table if not exists public.transactions (
  id bigserial primary key,
  user_email text not null,
  customer_name text not null,
  phone_number text,
  amount decimal(10,2) not null,
  charge decimal(10,2) default 0,
  include_charge boolean default false,
  total decimal(10,2) not null,
  type text not null,
  date timestamptz default now(),
  status text default 'Completed',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 3) Create a safe trigger function that will create a profile row when a new auth.user is inserted
create or replace function public.handle_new_user()
returns trigger as $$
begin
  -- Try to insert a minimal profile row using values we know exist
  insert into public.profiles (id, email, created_at)
  values (new.id, new.email, now());
  return new;
exception when unique_violation then
  -- if a profile already exists, ignore the error
  return new;
exception when others then
  -- If unexpected error occurs, log it and return new to avoid blocking auth flow
  perform pg_notify('handle_new_user_error', 'Error creating profile for user: ' || new.id || ' - ' || sqlerrm);
  return new;
end;
$$ language plpgsql security definer;

-- 4) Attach the trigger to auth.users insert (if no trigger exists)
drop trigger if exists handle_new_user_trigger on auth.users;
create trigger handle_new_user_trigger
after insert on auth.users
for each row execute function public.handle_new_user();

-- 5) Enable Row Level Security (RLS) on both tables
alter table public.profiles enable row level security;
alter table public.transactions enable row level security;

-- 6) Create RLS policies for profiles table
create policy "Users can view own profile" on public.profiles
  for select using (auth.uid() = id);

create policy "Users can insert own profile" on public.profiles
  for insert with check (auth.uid() = id);

create policy "Users can update own profile" on public.profiles
  for update using (auth.uid() = id);

-- 7) Create RLS policies for transactions table
create policy "Users can view own transactions" on public.transactions
  for select using (auth.jwt() ->> 'email' = user_email);

create policy "Users can insert own transactions" on public.transactions
  for insert with check (auth.jwt() ->> 'email' = user_email);

create policy "Users can update own transactions" on public.transactions
  for update using (auth.jwt() ->> 'email' = user_email);

create policy "Users can delete own transactions" on public.transactions
  for delete using (auth.jwt() ->> 'email' = user_email);

-- 8) Create indexes for better performance
create index if not exists idx_transactions_user_email on public.transactions(user_email);
create index if not exists idx_transactions_date on public.transactions(date);
create index if not exists idx_transactions_type on public.transactions(type);

-- 9) Grant necessary permissions
grant usage on schema public to anon, authenticated;
grant all on public.profiles to anon, authenticated;
grant all on public.transactions to anon, authenticated;
grant usage, select on all sequences in schema public to anon, authenticated;
