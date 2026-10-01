import { EventEmitter } from "node:events";
/**
 * Under Bun (the standalone `bask` executables), the `ws` package is swapped for a shim that
 * ignores `rejectUnauthorized`, so self-signed stations fail the TLS handshake. This wraps Bun's
 * native WebSocket, which takes TLS options, behind the small part of the `ws` API the client uses.
 */
export class BunSocket extends EventEmitter {
    socket;
    constructor(url, options) {
        super();
        const Native = globalThis.WebSocket;
        this.socket = new Native(url, {
            headers: options.headers,
            tls: { rejectUnauthorized: options.rejectUnauthorized, ...(options.ca ? { ca: options.ca } : {}) }
        });
        this.socket.binaryType = "arraybuffer";
        this.socket.onopen = () => this.emit("open");
        this.socket.onmessage = ({ data }) => typeof data === "string" ? this.emit("message", Buffer.from(data), false) : this.emit("message", Buffer.from(data), true);
        this.socket.onerror = (event) => this.emit("error", new Error(event?.message || "WebSocket connection failed"));
        this.socket.onclose = (event) => this.emit("close", event.code, Buffer.from(event.reason ?? ""));
    }
    get readyState() {
        return this.socket.readyState;
    }
    send(data, _options, callback) {
        try {
            this.socket.send(data);
            callback?.();
        }
        catch (error) {
            callback?.(error);
        }
    }
    close(code, reason) {
        this.socket.close(code, reason);
    }
    terminate() {
        this.socket.close();
    }
}
