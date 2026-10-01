import { EventEmitter } from "node:events";
/**
 * Under Bun (the standalone `bask` executables), the `ws` package is swapped for a shim that
 * ignores `rejectUnauthorized`, so self-signed stations fail the TLS handshake. This wraps Bun's
 * native WebSocket, which takes TLS options, behind the small part of the `ws` API the client uses.
 */
export declare class BunSocket extends EventEmitter {
    private readonly socket;
    constructor(url: string, options: {
        headers: Record<string, string>;
        rejectUnauthorized: boolean;
        ca?: string | Buffer;
    });
    get readyState(): number;
    send(data: Uint8Array, _options: unknown, callback?: (error?: Error) => void): void;
    close(code?: number, reason?: string): void;
    terminate(): void;
}
