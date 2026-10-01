export declare const API_VERSION = "1.7";
export declare const OPERATIONS: {
    readonly ping: {
        readonly gate: "none";
        readonly reply: "pong";
    };
    readonly capabilities: {
        readonly gate: "none";
        readonly reply: "capabilities_result";
    };
    readonly browse: {
        readonly gate: "none";
        readonly reply: "browse_result";
    };
    readonly describe: {
        readonly gate: "none";
        readonly reply: "describe_result";
    };
    readonly search: {
        readonly gate: "none";
        readonly reply: "search_result";
    };
    readonly read: {
        readonly gate: "none";
        readonly reply: "read_result";
    };
    readonly subscribe: {
        readonly gate: "none";
        readonly reply: "subscribed";
    };
    readonly unsubscribe: {
        readonly gate: "none";
        readonly reply: null;
    };
    readonly replace_subscriptions: {
        readonly gate: "none";
        readonly reply: "subscriptions_replaced";
    };
    readonly renew_subscriptions: {
        readonly gate: "none";
        readonly reply: "subscriptions_renewed";
    };
    readonly release_subscriptions: {
        readonly gate: "none";
        readonly reply: "subscriptions_released";
    };
    readonly subscription_status: {
        readonly gate: "none";
        readonly reply: "subscription_status_result";
    };
    readonly write: {
        readonly gate: "writes";
        readonly reply: "write_result";
    };
    readonly describe_write: {
        readonly gate: "none";
        readonly reply: "write_description";
    };
    readonly read_history: {
        readonly gate: "none";
        readonly reply: "history_result";
    };
    readonly describe_history: {
        readonly gate: "none";
        readonly reply: "history_description";
    };
    readonly read_history_rollup: {
        readonly gate: "none";
        readonly reply: "history_rollup_result";
    };
    readonly read_alarms: {
        readonly gate: "none";
        readonly reply: "alarms_result";
    };
    readonly ack_alarm: {
        readonly gate: "writes";
        readonly reply: "alarm_action_result";
    };
    readonly ack_alarms: {
        readonly gate: "writes";
        readonly reply: "alarm_action_result";
    };
    readonly clear_alarm: {
        readonly gate: "writes";
        readonly reply: "alarm_action_result";
    };
    readonly clear_alarms: {
        readonly gate: "writes";
        readonly reply: "alarm_action_result";
    };
    readonly subscribe_alarms: {
        readonly gate: "none";
        readonly reply: "alarms_subscribed";
    };
    readonly unsubscribe_alarms: {
        readonly gate: "none";
        readonly reply: "alarms_unsubscribed";
    };
    readonly read_schedule: {
        readonly gate: "none";
        readonly reply: "schedule_result";
    };
    readonly read_schedule_events: {
        readonly gate: "none";
        readonly reply: "schedule_events_result";
    };
    readonly write_schedule: {
        readonly gate: "writes";
        readonly reply: "schedule_write_result";
    };
    readonly subscribe_model: {
        readonly gate: "none";
        readonly reply: "model_subscribed";
    };
    readonly unsubscribe_model: {
        readonly gate: "none";
        readonly reply: "model_unsubscribed";
    };
    readonly read_tags: {
        readonly gate: "none";
        readonly reply: "tags_result";
    };
    readonly write_tags: {
        readonly gate: "writes";
        readonly reply: "tags_written";
    };
    readonly write_relations: {
        readonly gate: "writes";
        readonly reply: "relations_written";
    };
    readonly describe_component_types: {
        readonly gate: "none";
        readonly reply: "model_result";
    };
    readonly describe_component: {
        readonly gate: "none";
        readonly reply: "model_result";
    };
    readonly preview_model_changes: {
        readonly gate: "modelEdits";
        readonly reply: "model_result";
    };
    readonly apply_model_changes: {
        readonly gate: "modelEdits";
        readonly reply: "model_result";
    };
    readonly model_plan_status: {
        readonly gate: "none";
        readonly reply: "model_result";
    };
    readonly cancel_model_plan: {
        readonly gate: "none";
        readonly reply: "model_result";
    };
    readonly create_components: {
        readonly gate: "modelEdits";
        readonly reply: "model_result";
    };
    readonly update_component_properties: {
        readonly gate: "modelEdits";
        readonly reply: "model_result";
    };
    readonly rename_component: {
        readonly gate: "modelEdits";
        readonly reply: "model_result";
    };
    readonly move_components: {
        readonly gate: "modelEdits";
        readonly reply: "model_result";
    };
    readonly delete_components: {
        readonly gate: "modelEdits";
        readonly reply: "model_result";
    };
    readonly create_hierarchy: {
        readonly gate: "modelEdits";
        readonly reply: "model_result";
    };
    readonly configure_hierarchy: {
        readonly gate: "modelEdits";
        readonly reply: "model_result";
    };
};
export type OperationName = keyof typeof OPERATIONS;
export type Gate = (typeof OPERATIONS)[OperationName]["gate"];
export declare const ERROR_CODES: readonly ["alarm_failed", "auth_required", "bad_reference", "bad_request", "browse_failed", "children_present", "confirm_required", "cycle", "forbidden_action", "forbidden_alarm", "forbidden_component", "forbidden_point", "frozen_slot", "group_not_found", "history_failed", "idempotency_conflict", "illegal_parent", "implied_tag", "internal_error", "invalid_action", "invalid_alarm", "invalid_component", "invalid_link", "invalid_name", "invalid_point", "invalid_property", "invalid_slot", "invalid_type", "invalid_value", "model_busy", "model_change_failed", "model_edits_disabled", "model_limit", "name_conflict", "not_writable", "plan_closed", "plan_conflict", "plan_dependency", "plan_limit", "plan_mismatch", "plan_not_found", "protected_component", "read_failed", "readonly", "relation_failed", "relation_not_found", "relation_rejected", "response_too_large", "schedule_failed", "search_failed", "stale_plan", "subscription_limit", "tag_failed", "tag_not_found", "unknown_type", "unsupported_action", "unsupported_op", "write_cancelled", "write_failed", "writes_disabled"];
export type ErrorCode = (typeof ERROR_CODES)[number];
