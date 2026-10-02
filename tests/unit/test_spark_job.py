import pytest
import json
from spark.streaming_job import validate_payload, build_dlq_envelope
from schemas import validate_dlq

def test_validate_payload_valid_event():
    valid_event = json.dumps({
        "schema_version": "1.0",
        "event_id": "11111111-2222-3333-4444-555555555555",
        "user_id": "usr_01",
        "session_id": "ses_01",
        "event_type": "page_view",
        "page_url": "/home",
        "timestamp": "2026-09-18T10:00:00Z"
    })
    is_valid, err, ts = validate_payload(valid_event)
    assert is_valid is True
    assert err is None
    assert ts == "2026-09-18T10:00:00Z"

def test_validate_payload_missing_field():
    event = json.dumps({
        "schema_version": "1.0",
        "user_id": "usr_01",
        "session_id": "ses_01",
        "event_type": "page_view",
        "timestamp": "2026-09-18T10:00:00Z"
    })
    is_valid, err, _ = validate_payload(event)
    assert is_valid is False
    assert "Missing required fields" in err

def test_validate_payload_invalid_version():
    event = json.dumps({
        "schema_version": "2.0",
        "event_id": "11111111-2222-3333-4444-555555555555",
        "user_id": "usr_01",
        "session_id": "ses_01",
        "event_type": "page_view",
        "timestamp": "2026-09-18T10:00:00Z"
    })
    is_valid, err, _ = validate_payload(event)
    assert is_valid is False
    assert "Unsupported schema_version" in err

def test_validate_payload_invalid_event_type():
    event = json.dumps({
        "schema_version": "1.0",
        "event_id": "11111111-2222-3333-4444-555555555555",
        "user_id": "usr_01",
        "session_id": "ses_01",
        "event_type": "button_click",
        "timestamp": "2026-09-18T10:00:00Z"
    })
    is_valid, err, _ = validate_payload(event)
    assert is_valid is False
    assert "Invalid event_type" in err

def test_build_dlq_envelope_conforms_to_schema():
    raw_payload = "{\"malformed\": true"
    envelope_str = build_dlq_envelope(raw_payload, "schema_validation_error", "JSON parse error", partition=2, offset=42)
    envelope_dict = json.loads(envelope_str)

    # Validate against dlq_envelope.json schema
    is_valid, errors = validate_dlq(envelope_dict)
    assert is_valid is True, f"DLQ Envelope failed validation: {errors}"
    assert envelope_dict["source_partition"] == 2
    assert envelope_dict["source_offset"] == 42
    assert envelope_dict["failure_reason"] == "schema_validation_error"
