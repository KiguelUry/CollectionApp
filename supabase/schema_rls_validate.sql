-- =============================================================================
-- Validation après schema_rls_fix_live.sql
-- Supabase → SQL Editor → Run → compare les résultats ci-dessous
-- =============================================================================

-- 1) Anciennes policies DANGEREUSES : doit retourner 0 ligne
SELECT 'FAIL si des lignes ci-dessous' AS check_old_open_policies;
SELECT tablename, policyname
FROM pg_policies
WHERE schemaname = 'public'
  AND (
    policyname LIKE 'boardgames%'
    OR policyname LIKE '%all_authenticated%'
    OR policyname = 'Group creator can update'
  );

-- 2) RLS activé sur les tables sensibles
SELECT tablename, rowsecurity AS rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
    'collection_items',
    'friendships',
    'groups',
    'group_members',
    'locations',
    'collection_item_tags'
  )
ORDER BY tablename;

-- 3) Policies attendues (liste de référence)
SELECT 'Policies actuelles (public)' AS section;
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'collection_items',
    'collection_item_tags',
    'friendships',
    'groups',
    'group_members',
    'locations'
  )
ORDER BY tablename, policyname;

-- 4) Comptage rapide
SELECT tablename, count(*) AS policy_count
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'collection_items',
    'friendships',
    'groups',
    'group_members',
    'locations'
  )
GROUP BY tablename
ORDER BY tablename;
