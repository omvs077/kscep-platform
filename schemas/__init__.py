import os
import json
from jsonschema import Draft7Validator, FormatChecker

# Load schemas from JSON files
SCHEMAS_DIR = os.path.dirname(os.path.abspath(__file__))

with open(os.path.join(SCHEMAS_DIR, "event_v1.json"), "r") as f:
    EVENT_SCHEMA = json.load(f)

with open(os.path.join(SCHEMAS_DIR, "dlq_envelope.json"), "r") as f:
    DLQ_SCHEMA = json.load(f)

# Initialize validators with format checkers (e.g. for date-time, uuid)
event_validator = Draft7Validator(EVENT_SCHEMA, format_checker=FormatChecker())
dlq_validator = Draft7Validator(DLQ_SCHEMA, format_checker=FormatChecker())

def validate_event(data):
    """
    Validates data against the event_v1 schema.
    Returns (is_valid, errors_list)
    """
    errors = []
    for error in event_validator.iter_errors(data):
        # Format error path and message
        path = " -> ".join([str(p) for p in error.path]) if error.path else "root"
        errors.append(f"[{path}]: {error.message}")
    
    return len(errors) == 0, errors

def validate_dlq(data):
    """
    Validates data against the dlq_envelope schema.
    Returns (is_valid, errors_list)
    """
    errors = []
    for error in dlq_validator.iter_errors(data):
        path = " -> ".join([str(p) for p in error.path]) if error.path else "root"
        errors.append(f"[{path}]: {error.message}")
    
    return len(errors) == 0, errors
