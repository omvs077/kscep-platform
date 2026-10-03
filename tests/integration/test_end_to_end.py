import os
import json
import uuid
from datetime import datetime, timezone
import pytest
import jsonschema

SCHEMA_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "schemas",
    "event_v1.json"
)

@pytest.fixture(scope="module")
def event_schema():
    with open(SCHEMA_PATH, "r", encoding="utf-8") as f:
        return json.load(f)

def test_schema_file_loads(event_schema):
    assert event_schema is not None
    assert event_schema["$id"] == "kscep.event.v1"
    assert "schema_version" in event_schema["required"]

def test_valid_clickstream_event_validates(event_schema):
    event = {
        "schema_version": "1.0",
        "event_id": str(uuid.uuid4()),
        "user_id": "usr_test_1001",
        "session_id": "sess_test_9001",
        "event_type": "page_view",
        "page_url": "/products/electronics/headphones",
        "product_id": "prod_audio_01",
        "product_category": "Electronics",
        "price_inr": 2999.00,
        "timestamp": datetime.now(timezone.utc).isoformat()
    }
    jsonschema.validate(instance=event, schema=event_schema)

def test_missing_required_field_fails(event_schema):
    bad_event = {
        "schema_version": "1.0",
        "event_id": str(uuid.uuid4()),
        # missing user_id
        "session_id": "sess_test_9001",
        "event_type": "cart_add",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(instance=bad_event, schema=event_schema)

def test_invalid_event_type_fails(event_schema):
    bad_event = {
        "schema_version": "1.0",
        "event_id": str(uuid.uuid4()),
        "user_id": "usr_test_1001",
        "session_id": "sess_test_9001",
        "event_type": "invalid_unknown_action",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(instance=bad_event, schema=event_schema)

def test_invalid_schema_version_fails(event_schema):
    bad_event = {
        "schema_version": "2.0",
        "event_id": str(uuid.uuid4()),
        "user_id": "usr_test_1001",
        "session_id": "sess_test_9001",
        "event_type": "purchase",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(instance=bad_event, schema=event_schema)
