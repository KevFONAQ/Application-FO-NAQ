// Envoie une notification aux téléphones abonnés quand une actualité est publiée.
// Appelée par l'application juste après la publication (réservé aux administrateurs).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { buildPushHTTPRequest } from "npm:@pushforge/builder@2.0.5";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const vapid = Deno.env.get("VAPID_PRIVATE_KEY");
    if (!vapid) return json({ error: "Clé VAPID_PRIVATE_KEY absente des secrets" }, 500);

    // 1. L'appelant doit être administrateur (principal ou secondaire)
    const asUser = createClient(url, anon, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
    const { data: staff } = await asUser.rpc("is_staff");
    if (!staff) return json({ error: "Réservé aux administrateurs" }, 403);

    // 2. L'actualité et les abonnements (hors auteur)
    const { id } = await req.json();
    const db = createClient(url, service);
    const { data: n } = await db.from("news").select("*").eq("id", id).single();
    if (!n) return json({ error: "Actualité introuvable" }, 404);
    const text = String(n.body || n.link_url || (n.media_type === "video" ? "Nouvelle vidéo" : "Nouvelle photo"))
      .replace(/\s+/g, " ").trim().slice(0, 140);
    let q = db.from("push_subscriptions").select("endpoint,p256dh,auth");
    if (n.author_id) q = q.neq("user_id", n.author_id);
    const { data: subs, error } = await q;
    if (error) return json({ error: error.message }, 500);

    // 3. Envoi
    const privateJWK = JSON.parse(vapid);
    const adminContact = Deno.env.get("VAPID_SUBJECT") ?? "https://base-documentaire-fo-nouvelle-aquit-bay.vercel.app";
    let sent = 0;
    const dead: string[] = [];
    await Promise.all((subs ?? []).map(async (s) => {
      try {
        const r = await buildPushHTTPRequest({
          privateJWK,
          subscription: { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          message: {
            payload: { title: "FO France Travail NAQ", body: `${n.author_name ?? "FO"} : ${text}`, url: "/" },
            adminContact,
            options: { ttl: 43200, urgency: "normal" },
          },
        });
        const res = await fetch(r.endpoint, { method: "POST", headers: r.headers, body: r.body });
        if (res.status === 404 || res.status === 410) dead.push(s.endpoint);
        else if (res.ok) sent++;
      } catch (_) { /* un téléphone en erreur ne bloque pas les autres */ }
    }));
    if (dead.length) await db.from("push_subscriptions").delete().in("endpoint", dead);
    return json({ sent, removed: dead.length, total: subs?.length ?? 0 });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
