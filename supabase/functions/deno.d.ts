/** Types pour l’IDE (Cursor/VS Code). Exécution réelle : runtime Deno sur Supabase. */
declare namespace Deno {
  function serve(
    handler: (request: Request) => Response | Promise<Response>,
  ): void;

  const env: {
    get(key: string): string | undefined;
  };
}
