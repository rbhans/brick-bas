import { EventEmitter } from "node:events";
import { StationHttp, type StationHttpOptions } from "./http.js";
import { type OperationName } from "./operations.js";
import type { AlarmFilter, BrowseNode, Json, PointSnapshot, ScheduleEntry, Weekday } from "./types.js";
export interface ClientOptions extends StationHttpOptions {
    username?: string;
    /** Password, or a function that supplies it. Only called when a (re)login is needed. */
    password?: string | (() => string | Promise<string>);
    /** Reconnect and restore watches and alarm subscriptions after the connection drops. Default true. */
    reconnect?: boolean;
    /** Called whenever the session cookies change, so an app can save the session. */
    onSession?: (cookies: Record<string, string>) => void;
    /** Keepalive ping interval. Default: the station's heartbeat interval, else 25 s. */
    keepAliveMs?: number;
}
export interface CallOptions {
    timeoutMs?: number;
}
/**
 * A connection to one station's baskStream service.
 *
 * Events:
 * - `value` (PointSnapshot): one point changed (from COV frames and resync reads).
 * - `cov`, `alarm`, `model`, `resync`, `revoked`, `notice` (Json): raw server-initiated frames.
 * - `disconnected` ({ code, reason }), `reconnecting` ({ attempt, delayMs }), `reconnected` ().
 * - `error` (Error): a failure outside any request, such as a failed reconnect.
 */
export declare class BaskStreamClient extends EventEmitter {
    private readonly options;
    readonly http: StationHttp;
    /** The station's capabilities, loaded when the connection opens. */
    capabilities: Json;
    private ws?;
    private readonly pending;
    private nextId;
    private closedByUser;
    private reconnectAttempt;
    private reconnectTimer?;
    private keepAlive?;
    private readonly watches;
    private readonly alarmSubscriptions;
    constructor(options: ClientOptions);
    /** Logs in if needed, opens the WebSocket and loads capabilities. */
    static connect(options: ClientOptions): Promise<BaskStreamClient>;
    get connected(): boolean;
    open(): Promise<void>;
    /** Closes the connection and stops reconnecting. */
    close(): void;
    /**
     * Sends one request and resolves with the reply. Rejects with BaskStreamError, whose `code` is
     * the protocol error code (or a client code such as "timeout").
     */
    call(op: OperationName | string, fields?: Json, options?: CallOptions): Promise<Json>;
    ping(): Promise<Json>;
    browse(base?: string, options?: {
        depth?: number;
        metadata?: "none" | "full";
    }): Promise<BrowseNode>;
    describe(ord: string, metadata?: "none" | "full"): Promise<BrowseNode>;
    search(base: string, query: string, options?: Json): Promise<Json>;
    read(points: string[], fields?: string[]): Promise<PointSnapshot[]>;
    write(point: string, action: string, value?: unknown, options?: Json): Promise<PointSnapshot>;
    describeWrite(points: string[]): Promise<Json>;
    history(ord: string, options?: {
        start?: number;
        end?: number;
        limit?: number;
    }): Promise<Json>;
    historyRollup(ord: string, options: {
        start?: number;
        end?: number;
        interval: number;
        includeInvalid?: boolean;
    }): Promise<Json>;
    alarms(options?: {
        scope?: "open" | "ack_pending" | "all";
        limit?: number;
        order?: "newest" | "oldest";
        filter?: AlarmFilter;
        source?: string;
    }): Promise<Json>;
    ackAlarms(target: {
        uuids: string[];
    } | {
        filter: AlarmFilter;
        scope?: string;
        limit?: number;
    }, dryRun?: boolean): Promise<Json>;
    clearAlarms(target: {
        uuids: string[];
    } | {
        filter: AlarmFilter;
        scope?: string;
        limit?: number;
    }, dryRun?: boolean): Promise<Json>;
    schedule(ord: string, at?: number): Promise<Json>;
    scheduleEvents(ord: string, options?: {
        start?: number;
        end?: number;
        limit?: number;
    }): Promise<Json>;
    writeSchedule(ord: string, days: Partial<Record<Weekday, ScheduleEntry[]>>, dryRun?: boolean): Promise<Json>;
    subscriptionStatus(includePoints?: boolean): Promise<Json>;
    /**
     * Subscribes to live values for a set of points. The watch renews its lease, is restored after
     * a reconnect, re-reads its points after a resync, and emits `change` with each new snapshot.
     */
    watch(points: string[], options?: {
        group?: string;
        leaseSec?: number;
    }): Promise<Watch>;
    /** Live alarm events (`alarm` event). The subscription is restored after a reconnect. */
    subscribeAlarms(options?: {
        scope?: string;
        mode?: "event" | "snapshot" | "both";
        limit?: number;
        source?: string;
    }): Promise<Json>;
    /** @internal */
    forgetWatch(group: string): void;
    private ensureLogin;
    private openSocket;
    private onFrame;
    private deliver;
    private onClose;
    private failPending;
    private scheduleReconnect;
    private reconnect;
    private startKeepAlive;
    private stopKeepAlive;
}
/**
 * A named subscription group: the latest value of each point, lease renewal, and restoration
 * after reconnects. Emits `change` (PointSnapshot).
 */
export declare class Watch extends EventEmitter {
    private readonly client;
    readonly group: string;
    readonly leaseSec: number;
    readonly values: Map<string, PointSnapshot>;
    private points;
    private renewTimer?;
    constructor(client: BaskStreamClient, group: string, leaseSec: number);
    get pointOrds(): string[];
    /** Replaces the watched points and reads their current values. */
    update(points: string[]): Promise<PointSnapshot[]>;
    /** Re-reads every watched point (also done automatically after a resync). */
    refresh(): Promise<PointSnapshot[]>;
    /** Stops the watch and releases its subscriptions on the station. */
    close(): Promise<void>;
    /** @internal */
    accept(snapshot: PointSnapshot): void;
    /** @internal Re-creates the group after a reconnect. */
    restore(): Promise<void>;
    /** @internal */
    stopRenewing(): void;
    private startRenewing;
}
