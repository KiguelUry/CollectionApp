-- Perf lints Supabase (2026-11-24) :
-- - auth_rls_initplan : (select auth.uid()) au lieu de auth.uid()
-- - duplicate_index sur collection_items.location_user_id
-- - unindexed_foreign_keys (index couvrant les FK)
--
-- À exécuter dans le SQL Editor Supabase (idempotent autant que possible).
-- Ne change PAS la sémantique de sécurité — uniquement le plan d'exécution.

-- ─── Index dupliqué ───────────────────────────────────────────────────────────
DROP INDEX IF EXISTS public.boardgames_location_user_id_idx;

-- ─── Index FK manquants (échantillon utile) ───────────────────────────────────
CREATE INDEX IF NOT EXISTS activity_events_item_id_idx
  ON public.activity_events (item_id);
CREATE INDEX IF NOT EXISTS activity_reactions_user_id_idx
  ON public.activity_reactions (user_id);
CREATE INDEX IF NOT EXISTS app_notifications_sender_id_idx
  ON public.app_notifications (sender_id);
CREATE INDEX IF NOT EXISTS friendships_addressee_id_idx
  ON public.friendships (addressee_id);
CREATE INDEX IF NOT EXISTS group_members_profile_id_idx
  ON public.group_members (profile_id);
CREATE INDEX IF NOT EXISTS groups_created_by_idx
  ON public.groups (created_by);
CREATE INDEX IF NOT EXISTS locations_group_id_idx
  ON public.locations (group_id);
CREATE INDEX IF NOT EXISTS locations_created_by_idx
  ON public.locations (created_by);
CREATE INDEX IF NOT EXISTS marketplace_inquiries_sender_id_idx
  ON public.marketplace_inquiries (sender_id);
CREATE INDEX IF NOT EXISTS marketplace_inquiries_proposed_item_id_idx
  ON public.marketplace_inquiries (proposed_item_id);
CREATE INDEX IF NOT EXISTS group_wanted_posts_author_id_idx
  ON public.group_wanted_posts (author_id);
CREATE INDEX IF NOT EXISTS group_wanted_posts_item_id_idx
  ON public.group_wanted_posts (item_id);
CREATE INDEX IF NOT EXISTS group_wanted_posts_claimed_by_idx
  ON public.group_wanted_posts (claimed_by);
CREATE INDEX IF NOT EXISTS group_rule_entries_author_id_idx
  ON public.group_rule_entries (author_id);
CREATE INDEX IF NOT EXISTS group_rule_entries_item_id_idx
  ON public.group_rule_entries (item_id);
CREATE INDEX IF NOT EXISTS group_rule_votes_voter_id_idx
  ON public.group_rule_votes (voter_id);
CREATE INDEX IF NOT EXISTS group_holder_places_created_by_idx
  ON public.group_holder_places (created_by);
CREATE INDEX IF NOT EXISTS restaurant_visits_with_friend_id_idx
  ON public.restaurant_visits (with_friend_id);
CREATE INDEX IF NOT EXISTS user_quick_logs_item_id_idx
  ON public.user_quick_logs (item_id);

-- ─── auth_rls_initplan : réécriture générique des policies ────────────────────
-- Remplace auth.uid() / auth.role() par (select …) dans les expressions RLS.
-- Postgres évalue alors une fois par requête au lieu d'une fois par ligne.
DO $$
DECLARE
  pol record;
  new_using text;
  new_check text;
  cmd text;
BEGIN
  FOR pol IN
    SELECT
      n.nspname AS schemaname,
      c.relname AS tablename,
      p.polname AS policyname,
      CASE p.polcmd
        WHEN 'r' THEN 'SELECT'
        WHEN 'a' THEN 'INSERT'
        WHEN 'w' THEN 'UPDATE'
        WHEN 'd' THEN 'DELETE'
        WHEN '*' THEN 'ALL'
      END AS cmd,
      pg_get_expr(p.polqual, p.polrelid) AS using_expr,
      pg_get_expr(p.polwithcheck, p.polrelid) AS check_expr,
      p.polpermissive AS permissive,
      COALESCE(
        (
          SELECT string_agg(quote_ident(r.rolname), ', ')
          FROM pg_roles r
          WHERE r.oid = ANY (p.polroles)
        ),
        'public'
      ) AS roles
    FROM pg_policy p
    JOIN pg_class c ON c.oid = p.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND (
        COALESCE(pg_get_expr(p.polqual, p.polrelid), '') ~ 'auth\.(uid|role)\(\)'
        OR COALESCE(pg_get_expr(p.polwithcheck, p.polrelid), '') ~ 'auth\.(uid|role)\(\)'
      )
  LOOP
    new_using := pol.using_expr;
    new_check := pol.check_expr;
    IF new_using IS NOT NULL THEN
      new_using := regexp_replace(new_using, 'auth\.uid\(\)', '(select auth.uid())', 'g');
      new_using := regexp_replace(new_using, 'auth\.role\(\)', '(select auth.role())', 'g');
    END IF;
    IF new_check IS NOT NULL THEN
      new_check := regexp_replace(new_check, 'auth\.uid\(\)', '(select auth.uid())', 'g');
      new_check := regexp_replace(new_check, 'auth\.role\(\)', '(select auth.role())', 'g');
    END IF;

    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', pol.policyname, pol.schemaname, pol.tablename);

    cmd := format(
      'CREATE POLICY %I ON %I.%I AS %s FOR %s TO %s',
      pol.policyname,
      pol.schemaname,
      pol.tablename,
      CASE WHEN pol.permissive THEN 'PERMISSIVE' ELSE 'RESTRICTIVE' END,
      pol.cmd,
      pol.roles
    );
    IF pol.cmd = 'INSERT' THEN
      IF new_check IS NOT NULL THEN
        cmd := cmd || format(' WITH CHECK (%s)', new_check);
      ELSIF new_using IS NOT NULL THEN
        cmd := cmd || format(' WITH CHECK (%s)', new_using);
      END IF;
    ELSIF pol.cmd = 'UPDATE' THEN
      IF new_using IS NOT NULL THEN
        cmd := cmd || format(' USING (%s)', new_using);
      END IF;
      IF new_check IS NOT NULL THEN
        cmd := cmd || format(' WITH CHECK (%s)', new_check);
      ELSIF new_using IS NOT NULL THEN
        cmd := cmd || format(' WITH CHECK (%s)', new_using);
      END IF;
    ELSE
      IF new_using IS NOT NULL THEN
        cmd := cmd || format(' USING (%s)', new_using);
      END IF;
      IF new_check IS NOT NULL AND pol.cmd IN ('ALL') THEN
        cmd := cmd || format(' WITH CHECK (%s)', new_check);
      END IF;
    END IF;

    EXECUTE cmd;
  END LOOP;
END $$;
