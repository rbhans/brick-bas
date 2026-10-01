import http from "node:http";
export interface HttpResponse {
    status: number;
    headers: http.IncomingHttpHeaders;
    body: string;
}
export interface StationHttpOptions {
    /** Station base URL, e.g. https://192.168.0.126 */
    station: string;
    /** Verify the station's TLS certificate. Niagara stations often use self-signed certificates. */
    verifyTls?: boolean;
    /** Extra CA certificate(s) to trust. */
    ca?: string | Buffer;
    timeoutMs?: number;
    /** Restore a previously saved session. */
    cookies?: Record<string, string>;
}
/** HTTP side of a station connection: cookies, Niagara's SCRAM login and the health endpoint. */
export declare class StationHttp {
    readonly url: URL;
    readonly verifyTls: boolean;
    readonly ca?: string | Buffer;
    readonly timeoutMs: number;
    private readonly cookies;
    constructor(options: StationHttpOptions);
    /** The current session cookies, for saving a session between runs. */
    getCookies(): Record<string, string>;
    cookieHeader(): string;
    request(method: string, path: string, body?: string, headers?: Record<string, string>): Promise<HttpResponse>;
    /** The service's /stream/health JSON, or null when the session is not logged in. */
    health(): Promise<Record<string, unknown> | null>;
    /** Metrics text from /stream/metrics (OpenMetrics format). */
    metrics(): Promise<string>;
    /**
     * Niagara web login (SCRAM-SHA-256), verifying the station's signature. Reuses an existing
     * session when its cookies are still valid.
     */
    login(username: string, password: string): Promise<Record<string, unknown>>;
    private storeCookies;
}
