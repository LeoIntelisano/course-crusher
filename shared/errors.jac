"""Turn a failed server call into a sentence a student can act on.

A failed RPC surfaces in the browser as an error whose text embeds the server's
JSON envelope, e.g. `get_today: Function get_today failed: {"ok": false, ...
"error": {"code": "UNAUTHORIZED", "message": "Unauthorized"}}`. No imports, so
the same code runs in the bundle and in `jac test`.
"""

glob GENERIC_FAILURE: str = "Couldn't reach CourseCrusher. Check your connection and try again.";
glob SESSION_EXPIRED: str = "Your session expired. Sign in again.";
glob SERVER_FAILURE: str = "Something went wrong on our side. Try again in a moment.";
glob MESSAGE_KEY: str = "\"message\": \"";

def is_unauthorized(failure: object) -> bool {
    return "UNAUTHORIZED" in str(failure);
}

"""The envelope's `message`, or None when the text carries no envelope."""
def envelope_message(text: str) -> str | None {
    start = text.find(MESSAGE_KEY);
    if start < 0 {
        return None;
    }
    rest = text[start + len(MESSAGE_KEY):];
    end = rest.find("\"");
    if end <= 0 {
        return None;
    }
    return rest[:end];
}

def error_message(failure: object) -> str {
    if is_unauthorized(failure) {
        return SESSION_EXPIRED;
    }
    text = str(failure);
    if "EXECUTION_ERROR" in text or "INTERNAL" in text {
        return SERVER_FAILURE;
    }
    message = envelope_message(text);
    if message {
        return message;
    }
    return GENERIC_FAILURE;
}
