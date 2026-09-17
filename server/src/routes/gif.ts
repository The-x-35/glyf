import type { FastifyInstance } from "fastify";

/** GIF search for the keyboard's media panel (Gboard-style). iOS keyboards
 *  cannot type images — the panel copies the GIF to the pasteboard and the
 *  user pastes it — but SEARCH goes through here so the provider key stays
 *  server-side (§1.6). Works with a free GIPHY key: set GIPHY_API_KEY in
 *  server/.env. Until then the route reports the missing state cleanly. */
export function gifRoutes(app: FastifyInstance): void {

  app.get<{ Querystring: { q?: string; limit?: string } }>(
    "/gif/search", async (req, reply) => {
      const key = process.env.GIPHY_API_KEY;
      if (!key) {
        return reply.code(503).send({
          error: "GIF search isn't available yet",
        });
      }
      const q = (req.query.q ?? "").slice(0, 80);
      const limit = Math.min(Number(req.query.limit ?? 24) || 24, 50);
      const endpoint = q
        ? `https://api.giphy.com/v1/gifs/search?api_key=${key}&q=${encodeURIComponent(q)}&limit=${limit}&rating=pg-13`
        : `https://api.giphy.com/v1/gifs/trending?api_key=${key}&limit=${limit}&rating=pg-13`;
      const res = await fetch(endpoint, { signal: AbortSignal.timeout(6000) });
      if (!res.ok) return reply.code(502).send({ error: "GIF provider error" });
      const body = await res.json() as {
        data: { id: string; title: string; images: {
          fixed_width_small: { url: string; width: string; height: string };
          original: { url: string };
        } }[];
      };
      return {
        gifs: body.data.map(g => ({
          id: g.id,
          title: g.title,
          preview: g.images.fixed_width_small.url,
          url: g.images.original.url,
        })),
      };
    });
}
