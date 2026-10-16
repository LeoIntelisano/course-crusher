"""Helpers for endpoint tests: an in-process server with a signed-in student.

Each client gets its own temporary data directory, so tests never share or
leave behind graph state.
"""

import tempfile;
import from jaclang.testing.testing { JacTestClient, TestResponse }

glob WEB_ENTRY: str = "web.jac";
glob TEST_PASSWORD: str = "correct-horse-battery-staple";

def anonymous_client -> JacTestClient {
    return JacTestClient.from_file(WEB_ENTRY, base_path=tempfile.mkdtemp(prefix="course-crusher-test-"));
}

"""Register `email` and keep its token on the client for later calls."""
def sign_up(client: JacTestClient, email: str) {
    response = client.register_user(email, TEST_PASSWORD);
    assert response.status_code == 201, f"registering {email} failed: {response.text}";
}

def signed_in_client(email: str = "student@example.com") -> JacTestClient {
    client = anonymous_client();
    sign_up(client, email);
    return client;
}

def post(client: JacTestClient, endpoint: str, payload: dict[str, any] | None = None) -> TestResponse {
    return client.post(f"/function/{endpoint}", json=payload or {});
}

"""Call an endpoint and return its decoded result, failing the test on a non-OK envelope."""
def call(client: JacTestClient, endpoint: str, payload: dict[str, any] | None = None) -> any {
    response = post(client, endpoint, payload);
    assert response.ok, f"{endpoint} failed ({response.status_code}): {response.text}";
    data = response.data;
    assert data is not None, f"{endpoint} returned no data";
    return data["result"];
}
