"""Whether the server is set up to call a model, and what to say when a call fails.

byLLM maps some provider errors to its own classes (AuthenticationError,
RateLimitError, ...) and lets the rest escape as the provider's exception, so
failures are matched on class names along the MRO. That keeps the messages
working across byLLM and LiteLLM versions without importing either.
"""

import os;

glob DEFAULT_MODEL: str = "gpt-4o-mini";
glob MODEL_ENV: str = "LLM_MODEL";
glob FIXTURE_MODEL: str = "fixture";
glob AI_UNAVAILABLE: str = "The AI isn't available right now. Try again in a minute.";

"""Model-name prefix to the environment variable LiteLLM reads its key from. First match wins."""
glob PROVIDER_KEYS: list[tuple[str, str]] = [
    ("anthropic/", "ANTHROPIC_API_KEY"),
    ("claude", "ANTHROPIC_API_KEY"),
    ("gemini", "GEMINI_API_KEY"),
    ("openai/", "OPENAI_API_KEY"),
    ("gpt", "OPENAI_API_KEY"),
    ("o1", "OPENAI_API_KEY"),
    ("o3", "OPENAI_API_KEY"),
    ("o4", "OPENAI_API_KEY")
];

glob KEY_REJECTED: str = "The AI provider rejected this server's API key. Check the key in .env and restart the server.";
glob MODEL_MISSING: str = "The AI model this server is set to use isn't available. Check LLM_MODEL in .env.";
glob TOO_SLOW: str = "The AI took too long to answer. Try again.";

glob FAILURE_MESSAGES: dict[str, str] = {
    "AuthenticationError": KEY_REJECTED,
    "PermissionDeniedError": KEY_REJECTED,
    "RateLimitError": "The AI provider is busy or out of quota. Try again in a minute.",
    "ModelNotFoundError": MODEL_MISSING,
    "NotFoundError": MODEL_MISSING,
    "LLMTimeout": TOO_SLOW,
    "Timeout": TOO_SLOW,
    "APIConnectionError": "The server couldn't reach the AI provider. Check its internet connection.",
    "OutputConversionError": "The AI's answer came back in a shape we couldn't read. Try again.",
    "ContextWindowExceededError": "That's too long for the AI. Paste a shorter description.",
    "BadRequestError": "The AI provider rejected the request. Check LLM_MODEL and the API key in .env."
};

"""Whether the server can call a model, and what to tell the student when it can't."""
obj AiStatus {
    has ready: bool;
    has model: str;
    has message: str = "";
}

def configured_model(env: dict[str, str]) -> str {
    return env.get(MODEL_ENV, "").strip() or DEFAULT_MODEL;
}

"""The environment variable holding `model`'s key, or "" when the provider needs none we know of."""
def key_env_for(model: str) -> str {
    name = model.strip().lower();
    for (prefix, env_name) in PROVIDER_KEYS {
        if name.startswith(prefix) {
            return env_name;
        }
    }
    return "";
}

def ai_status_for(env: dict[str, str], fixture: bool) -> AiStatus {
    if fixture {
        return AiStatus(ready=True, model=FIXTURE_MODEL);
    }
    model = configured_model(env);
    key_name = key_env_for(model);
    if key_name and not env.get(key_name, "").strip() {
        return AiStatus(
            ready=False,
            model=model,
            message=f"AI isn't set up on this server yet: {key_name} is missing for {model}. Add it to .env and restart the server."
        );
    }
    return AiStatus(ready=True, model=model);
}

"""The status for this process's environment."""
def current_ai_status(fixture_env: str) -> AiStatus {
    env = dict(os.environ);
    return ai_status_for(env, bool(env.get(fixture_env, "").strip()));
}

def error_names(err: Exception) -> list[str] {
    return [cls.__name__ for cls in type(err).__mro__];
}

"""A sentence the student can act on, most specific error class first."""
def failure_message(err: Exception, fallback: str = AI_UNAVAILABLE) -> str {
    for name in error_names(err) {
        if name in FAILURE_MESSAGES {
            return FAILURE_MESSAGES[name];
        }
    }
    return fallback;
}
