obj AuthenticationError(Exception) {}
obj RateLimitError(Exception) {}
obj BadRequestError(Exception) {}
obj ContextWindowExceededError(BadRequestError) {}
obj SomethingNew(Exception) {}

test "the default model needs an OpenAI key" {
    status = ai_status_for({}, False);

    assert not status.ready;
    assert status.model == "gpt-4o-mini";
    assert "OPENAI_API_KEY is missing" in status.message;
}

test "a configured key makes the AI ready" {
    status = ai_status_for({"OPENAI_API_KEY": "sk-test"}, False);

    assert status.ready and status.message == "";
}

test "a blank key counts as missing" {
    assert not ai_status_for({"OPENAI_API_KEY": "   "}, False).ready;
}

test "Claude models look for the Anthropic key" {
    env = {"LLM_MODEL": "claude-sonnet-4-6", "OPENAI_API_KEY": "sk-test"};

    status = ai_status_for(env, False);

    assert not status.ready;
    assert "ANTHROPIC_API_KEY" in status.message;
    assert ai_status_for({**env, "ANTHROPIC_API_KEY": "sk-ant-test"}, False).ready;
}

test "providers with no known key are trusted" {
    assert key_env_for("ollama/llama3") == "";
    assert ai_status_for({"LLM_MODEL": "ollama/llama3"}, False).ready;
}

test "fixture mode is always ready" {
    status = ai_status_for({}, True);

    assert status.ready and status.model == "fixture";
}

test "provider prefixes map to their key" {
    assert key_env_for("anthropic/claude-haiku-4-5") == "ANTHROPIC_API_KEY";
    assert key_env_for("gemini/gemini-2.5-flash") == "GEMINI_API_KEY";
    assert key_env_for("openai/gpt-4o") == "OPENAI_API_KEY";
    assert key_env_for(" GPT-4o-mini ") == "OPENAI_API_KEY";
}

test "known failures get a specific message" {
    assert failure_message(AuthenticationError("bad key")) == KEY_REJECTED;
    assert "busy" in failure_message(RateLimitError("429"));
}

test "the most specific error class wins" {
    message = failure_message(ContextWindowExceededError("too long"));

    assert "too long for the AI" in message;
}

test "unknown failures fall back" {
    assert failure_message(SomethingNew("boom")) == AI_UNAVAILABLE;
    assert failure_message(SomethingNew("boom"), "Custom fallback") == "Custom fallback";
}
