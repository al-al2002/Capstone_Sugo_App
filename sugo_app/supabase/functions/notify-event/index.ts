/**
 * Push notifications for things that happen in the database.
 *
 * ```
 * POST /functions/v1/notify-event          header: x-cron-secret: <CRON_SECRET>
 * { "type": "message",       "message_id": "uuid" }
 * { "type": "stage",         "job_id": "uuid", "stage": "collected" }
 * { "type": "return_method", "job_id": "uuid", "method": "client_pickup" }
 * ```
 *
 * ## Who calls this
 *
 * Only the database. Three triggers (20260922000006) post here through
 * `pg_net` when a chat message is saved, when a pickup job changes stage, and
 * when a client chooses how they want their unit back. Those writes come
 * straight from the apps under RLS, so there is no server code of ours in the
 * path to send a push from - a trigger is the one place that sees every one of
 * them, whichever build of the app made the write.
 *
 * It carries the same `x-cron-secret` the ETA sweep uses (read from Vault by
 * the trigger), so nobody else can make SUGO notify people.
 *
 * ## Why the payload is ids, not text
 *
 * The trigger sends what happened; this function reads who it happened to and
 * what to say from the database itself. A request that named its own
 * recipient and wording would be a way to push anything to anyone, secret or
 * no secret, the day the secret leaked.
 *
 * ## Why push at all when Realtime exists
 *
 * Realtime reaches an open app. These reach a phone in a pocket - a reply
 * from the technician, the unit collected, a job request - which is exactly
 * when people are not looking at the app.
 */
import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { deviceNoun, firstNameOf, notifyUser, preview } from "../_shared/notify.ts";

interface EventRequest {
  type?: "message" | "stage" | "return_method";
  message_id?: string;
  job_id?: string;
  stage?: string;
  method?: string;
}

interface JobRow {
  id: string;
  client_id: string;
  assigned_technician_id: string | null;
  device_type: string | null;
}

/** What the client is told as their unit moves. */
function stageCopy(
  stage: string,
  technician: string,
  noun: string,
): { title: string; body: string } | null {
  switch (stage) {
    case "heading_to_pickup":
      return {
        title: "Your technician is on the way",
        body: `${technician} is heading over to collect your ${noun}.`,
      };
    case "collected":
      return {
        title: "Picked up",
        body: `${technician} has collected your ${noun}.`,
      };
    case "returning_to_shop":
      return {
        title: "Heading to the shop",
        body: `Your ${noun} is on its way to the workshop.`,
      };
    case "in_repair":
      return {
        title: "Repair started",
        body: `${technician} has started work on your ${noun}.`,
      };
    case "out_for_delivery":
      return {
        title: "Out for delivery",
        body: `Your ${noun} is fixed and on its way back to you.`,
      };
    case "ready_for_collection":
      return {
        title: "Ready for pick-up",
        body: `Your ${noun} is fixed and waiting for you at the shop.`,
      };
    case "delivered":
      return {
        title: "Delivered",
        body: `Your ${noun} is back with you.`,
      };
    default:
      return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  try {
    const expected = Deno.env.get("CRON_SECRET");
    if (!expected) {
      console.warn("CRON_SECRET is not set; notifications are disabled");
      return fail("Notifications are not configured", 503);
    }
    if (req.headers.get("x-cron-secret") !== expected) {
      return fail("Not authorised", 401);
    }

    const body = (await req.json()) as EventRequest;
    const db = serviceClient();

    // ------------------------------------------------------------ message
    if (body.type === "message") {
      if (!body.message_id) return fail("message_id is required", 422);

      const { data: message } = await db
        .from("job_messages")
        .select("id, job_id, sender_id, body, image_path")
        .eq("id", body.message_id)
        .maybeSingle<
          {
            id: string;
            job_id: string;
            sender_id: string;
            body: string;
            image_path: string | null;
          }
        >();
      if (!message) return json({ sent: 0, reason: "message_not_found" });

      const job = await loadJob(db, message.job_id);
      if (!job) return json({ sent: 0, reason: "job_not_found" });

      // To whoever did not write it.
      const recipient = message.sender_id === job.client_id
        ? job.assigned_technician_id
        : job.client_id;
      const sender = await firstNameOf(db, message.sender_id, "New message");

      // A photo with no caption would otherwise push an empty line. The
      // notification says a photo arrived; it never carries the image or its
      // URL, because a private bucket's contents have no business in a push
      // payload that the OS may log.
      const hasPhoto = Boolean(message.image_path);
      const text = (message.body ?? "").trim();
      const messageBody = hasPhoto
        ? (text.length > 0 ? `📷 ${preview(text)}` : "📷 Sent a photo")
        : preview(text);

      const sent = await notifyUser(db, recipient, {
        title: sender,
        body: messageBody,
        // The name rides along so a tap can title the chat it opens.
        data: { type: "message", job_id: job.id, name: sender },
      });
      return json({ sent });
    }

    // -------------------------------------------------------------- stage
    if (body.type === "stage") {
      if (!body.job_id || !body.stage) return fail("job_id and stage are required", 422);

      const job = await loadJob(db, body.job_id);
      if (!job) return json({ sent: 0, reason: "job_not_found" });

      const technician = await firstNameOf(db, job.assigned_technician_id, "Your technician");
      const copy = stageCopy(body.stage, technician, deviceNoun(job.device_type));
      if (!copy) return json({ sent: 0, reason: "unknown_stage" });

      const sent = await notifyUser(db, job.client_id, {
        ...copy,
        data: { type: "stage", job_id: job.id, stage: body.stage },
      });
      return json({ sent });
    }

    // ------------------------------------------------------ return method
    if (body.type === "return_method") {
      if (!body.job_id || !body.method) return fail("job_id and method are required", 422);

      const job = await loadJob(db, body.job_id);
      if (!job) return json({ sent: 0, reason: "job_not_found" });

      const client = await firstNameOf(db, job.client_id, "The client");
      const noun = deviceNoun(job.device_type);
      const pickup = body.method === "client_pickup";

      const sent = await notifyUser(db, job.assigned_technician_id, {
        title: pickup ? `${client} will pick it up` : `${client} wants it delivered`,
        body: pickup
          ? `No delivery trip for the ${noun} - they will collect it at your shop.`
          : `Bring the ${noun} back to them once it is fixed.`,
        data: { type: "return_method", job_id: job.id, method: body.method },
      });
      return json({ sent });
    }

    return fail("Unknown event type", 422);
  } catch (error) {
    return fail("Could not send the notification", 500, (error as Error).message);
  }
});

async function loadJob(
  db: ReturnType<typeof serviceClient>,
  jobId: string,
): Promise<JobRow | null> {
  const { data } = await db
    .from("jobs")
    .select("id, client_id, assigned_technician_id, device_type")
    .eq("id", jobId)
    .maybeSingle<JobRow>();
  return data ?? null;
}
