-- ============================================================================
-- midday database bootstrap - SUPABASE-ADAPTED
-- Adapted by CTO 2026-08-31 from packages/db/src/test/helpers/setup-test-db.sql
-- (upstream midday-ai/midday @ 5158731). Run in the Supabase SQL editor
-- BEFORE drizzle-kit push. Safe to run more than once.
--
-- WHY THIS FILE EXISTS
-- The upstream helper targets a bare Postgres container. On Supabase three of
-- its statements must NOT be run, and two things it omits are required:
--
--   SKIPPED  CREATE SCHEMA auth        - Supabase already has it.
--   SKIPPED  CREATE FUNCTION auth.uid()  } Supabase's real versions read the
--   SKIPPED  CREATE FUNCTION auth.jwt()  } caller's token. The upstream stubs
--                                        } return a fixed nil UUID and an empty
--                                        } object, and CREATE OR REPLACE would
--                                        } overwrite the real ones. Nothing
--                                        } would error - every row-level
--                                        } security rule would simply start
--                                        } answering as the nil user.
--
--   ADDED    CREATE EXTENSION pg_trgm  - schema.ts uses gin_trgm_ops four times
--                                        and gist_trgm_ops once. Upstream never
--                                        creates it.
--   ADDED    IMMUTABLE on the two inbox functions - the inbox.fts column is a
--                                        stored generated column, and Postgres
--                                        rejects a generation expression whose
--                                        function is not immutable.
--
-- Verified 2026-08-31 against a fresh Supabase project: all statements applied,
-- and a subsequent `drizzle-kit push` produced 49 tables, 110 RLS policies and
-- 231 indexes with a working write round-trip.
-- ============================================================================

-- Adds pgvector, so the two 768-dimension embedding columns can be created
-- (schema.ts:312 and schema.ts:330).
create extension if not exists vector with schema extensions;

-- Adds trigram text matching, required by the indexes that use gin_trgm_ops
-- and gist_trgm_ops (schema.ts:436, 451, 1390, 1798, 1802, 2529).
create extension if not exists pg_trgm with schema extensions;

-- Creates the "private" schema. Supabase does not provide it; 44 security
-- rules in schema.ts call a function that has to live inside it.
create schema if not exists private;

-- Placeholder "which teams is the signed-in user a member of?" - returns an
-- empty list. Only has to exist so the security rules can be created. Replace
-- with a real implementation before this database serves more than one team.
create or replace function private.get_teams_for_authenticated_user()
  returns setof uuid
  language sql
as $$ select '00000000-0000-0000-0000-000000000000'::uuid limit 0 $$;

-- Placeholder that pulls product names out of an inbox item's JSON; always
-- returns an empty string. Must exist before the "inbox" table can be created,
-- because one of that table's columns is computed with it (schema.ts:2485).
-- NOTE: inbox.fts is a STORED generated column, so the value this returns is
-- written at insert time. Replace it before real inbox data lands, or product
-- names will be permanently missing from inbox search.
create or replace function extract_product_names(data json)
  returns text
  language sql
  immutable
as $$ select '' $$;

-- Builds the searchable text blob for an inbox item. Same story: must exist
-- before "inbox" is created, and must be declared immutable.
create or replace function generate_inbox_fts(name text, products text)
  returns tsvector
  language sql
  immutable
as $$ select to_tsvector('english'::regconfig,
                         coalesce(name, '') || ' ' || coalesce(products, '')) $$;

-- Read back what was actually created, so the result is observed not assumed.
-- Expect exactly 6 rows, and NOTHING labelled "control".
select 'extension' as kind, e.extname as name, n.nspname as in_schema
  from pg_extension e join pg_namespace n on n.oid = e.extnamespace
 where e.extname in ('vector', 'pg_trgm')
union all
select 'schema', nspname, '' from pg_namespace where nspname = 'private'
union all
select 'function', p.proname, n.nspname
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where p.proname in ('get_teams_for_authenticated_user',
                     'extract_product_names', 'generate_inbox_fts')
union all
select 'control - MUST BE ABSENT', p.proname, n.nspname
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where p.proname = 'enigma_control_no_such_function';
