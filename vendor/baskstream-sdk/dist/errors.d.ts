/** A request the station answered with an error, or a client-side failure with a stable code. */
export declare class BaskStreamError extends Error {
    /** Protocol error code (see spec/baskstream-protocol.json), or a client code such as "timeout". */
    readonly code: string;
    /** The operation that failed, when known. */
    readonly op?: string | undefined;
    constructor(
    /** Protocol error code (see spec/baskstream-protocol.json), or a client code such as "timeout". */
    code: string, message: string, 
    /** The operation that failed, when known. */
    op?: string | undefined);
}
/** Client-side codes, alongside the protocol's own. */
export declare const CLIENT_ERRORS: {
    readonly timeout: "timeout";
    readonly notConnected: "not_connected";
    readonly closed: "connection_closed";
    readonly loginFailed: "login_failed";
    readonly sessionExpired: "session_expired";
    readonly badMessage: "bad_message";
};
