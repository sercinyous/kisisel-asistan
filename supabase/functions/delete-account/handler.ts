// delete-account isteğinin akışı. Veritabanı dışarıdan verilir (index.ts
// service_role istemcisini bağlar), böylece bu dosya Node ile sınanabilir.
import { appleCodeFrom, hasAppleProvider } from "./apple.ts";
import {
  type DeletionStep,
  DELETION_STEPS,
  extractBearer,
  isConfirmed,
  jsonResponse,
  MAX_BODY_BYTES,
  MESSAGES,
  normalizeEmail,
  CORS_HEADERS,
} from "./logic.ts";

export interface AuthUser {
  id: string;
  email: string | null;
  /** Bağlı kimlik sağlayıcıları (ör. "email", "google", "apple"). */
  providers?: string[];
}

/** service_role ile yapılan işlemler (yalnızca sunucuda). */
export interface AccountStore {
  /** Kullanıcı JWT'sini doğrular; geçersizse null. */
  userFromJwt(token: string): Promise<AuthUser | null>;
  /** Kullanıcının iki yöndeki tüm arkadaşlıkları. */
  deleteFriendships(userId: string): Promise<void>;
  /** Kullanıcının gönderdiği ve ona gelen (kimlik ya da e-postayla) tüm istekler. */
  deleteFriendRequests(userId: string, email: string | null): Promise<void>;
  /** Storage `avatars` kovasında kullanıcının `<uid>/` klasöründeki tüm nesneler. */
  deleteAvatars(userId: string): Promise<void>;
  /** Storage `body_photos` kovasında `<uid>/` altındaki tüm ilerleme fotoğrafları. */
  deleteBodyPhotos(userId: string): Promise<void>;
  /** auth.users satırı; geri kalan public satırları ON DELETE CASCADE ile gider. */
  deleteAuthUser(userId: string): Promise<void>;
}

export interface HandlerDeps {
  store: AccountStore;
  log: (message: string) => void;
  /**
   * Apple yetki kodunu belirtece çevirip iptal eder. Gizli anahtarlar eksikse
   * null: iptal atlanır ve günlüğe yazılır.
   */
  revokeApple?: ((authorizationCode: string) => Promise<void>) | null;
}

export function createHandler(deps: HandlerDeps): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
    if (req.method !== "POST") return jsonResponse(405, { ok: false, error: MESSAGES.method });

    const token = extractBearer(req.headers.get("authorization"));
    if (token === null) return jsonResponse(401, { ok: false, error: MESSAGES.unauthorized });

    let user: AuthUser | null;
    try {
      user = await deps.store.userFromJwt(token);
    } catch (e) {
      deps.log(`delete-account: jwt doğrulanamadı: ${String(e)}`);
      user = null;
    }
    if (user === null) return jsonResponse(401, { ok: false, error: MESSAGES.unauthorized });

    let body: unknown = null;
    try {
      const text = await req.text();
      if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) {
        return jsonResponse(400, { ok: false, error: MESSAGES.badRequest });
      }
      body = text.length === 0 ? null : JSON.parse(text);
    } catch {
      body = null;
    }
    if (!isConfirmed(body)) return jsonResponse(400, { ok: false, error: MESSAGES.badRequest });

    // Apple belirteci iptali silmeden önce denenir; başarısızlık silmeyi engellemez.
    if (hasAppleProvider(user.providers)) {
      const code = appleCodeFrom(body);
      const revoke = deps.revokeApple ?? null;
      if (revoke === null) {
        deps.log("delete-account: apple iptali atlandı: APPLE_* gizli anahtarları eksik");
      } else if (code === null) {
        deps.log("delete-account: apple iptali atlandı: yetki kodu gönderilmedi");
      } else {
        try {
          await revoke(code);
        } catch (e) {
          deps.log(`delete-account: apple iptali başarısız: ${String(e)}`);
        }
      }
    }

    const email = normalizeEmail(user.email);
    const run: Record<DeletionStep, () => Promise<void>> = {
      friendships: () => deps.store.deleteFriendships(user.id),
      friend_requests: () => deps.store.deleteFriendRequests(user.id, email),
      avatars: () => deps.store.deleteAvatars(user.id),
      body_photos: () => deps.store.deleteBodyPhotos(user.id),
      auth_user: () => deps.store.deleteAuthUser(user.id),
    };
    for (const step of DELETION_STEPS) {
      try {
        await run[step]();
      } catch (e) {
        // Kullanıcı kimliği günlüğe yazılmaz; yalnızca adım ve hata.
        deps.log(`delete-account: ${step} başarısız: ${String(e)}`);
        return jsonResponse(500, { ok: false, error: MESSAGES.failed });
      }
    }
    return jsonResponse(200, { ok: true });
  };
}
