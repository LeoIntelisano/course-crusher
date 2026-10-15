glob UNAUTHORIZED_TEXT: str = "Error: get_today: Function get_today failed: {\"ok\": false, \"type\": \"error\", \"data\": null, \"error\": {\"code\": \"UNAUTHORIZED\", \"message\": \"Unauthorized\"}}";
glob EXECUTION_TEXT: str = "Error: explode: Function explode failed: {\"ok\": false, \"type\": \"error\", \"data\": null, \"error\": {\"code\": \"EXECUTION_ERROR\", \"message\": \"KeyError: 'secret_field' in /srv/app.py\"}}";
glob VALIDATION_TEXT: str = "Error: add_course: Function add_course failed: {\"ok\": false, \"error\": {\"code\": \"VALIDATION_ERROR\", \"message\": \"Field required: code\"}}";

test "an expired session is recognized and explained" {
    assert is_unauthorized(UNAUTHORIZED_TEXT);
    assert error_message(UNAUTHORIZED_TEXT) == SESSION_EXPIRED;
    assert not is_unauthorized(VALIDATION_TEXT);
}

test "server crashes never leak their internals" {
    message = error_message(EXECUTION_TEXT);
    assert message == SERVER_FAILURE;
    assert "secret_field" not in message and "/srv" not in message;
}

test "an envelope message is passed through" {
    assert envelope_message(VALIDATION_TEXT) == "Field required: code";
    assert error_message(VALIDATION_TEXT) == "Field required: code";
}

test "anything else gets the generic network message" {
    assert error_message("TypeError: Failed to fetch") == GENERIC_FAILURE;
    assert envelope_message("no envelope here") is None;
    assert envelope_message("\"message\": \"") is None;
}
