/** A request the station answered with an error, or a client-side failure with a stable code. */
export class BaskStreamError extends Error {
    code;
    op;
    constructor(
    /** Protocol error code (see spec/baskstream-protocol.json), or a client code such as "timeout". */
    code, message, 
    /** The operation that failed, when known. */
    op) {
        super(message);
        this.code = code;
        this.op = op;
        this.name = "BaskStreamError";
    }
}
/** Client-side codes, alongside the protocol's own. */
export const CLIENT_ERRORS = {
    timeout: "timeout",
    notConnected: "not_connected",
    closed: "connection_closed",
    loginFailed: "login_failed",
    sessionExpired: "session_expired",
    badMessage: "bad_message"
};
