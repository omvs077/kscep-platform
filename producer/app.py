import os
import time
import uuid
import json
import random
import threading
from datetime import datetime, timezone
from flask import Flask, jsonify, request, render_template_string
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from prometheus_client import Counter, Gauge, generate_latest, CONTENT_TYPE_LATEST
from confluent_kafka import Producer

# Import schemas package
import sys
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import schemas

app = Flask(__name__)

# Initialize rate limiter
limiter = Limiter(
    key_func=get_remote_address,
    app=app,
    default_limits=["100 per minute"]
)

# API Key Protection
ADMIN_API_KEY = os.environ.get("ADMIN_API_KEY", "default-dev-key")

# Prometheus Metrics
EVENTS_PUBLISHED = Counter("producer_events_published_total", "Total events successfully published to Kafka", ["event_type"])
EVENTS_REJECTED = Counter("producer_events_rejected_total", "Total events rejected by schema validation", ["reason"])
CURRENT_RATE = Gauge("producer_current_rate_events_per_sec", "Current event generation rate")

# Global Simulator State
class TrafficSimulator:
    def __init__(self):
        self.pattern = "steady"  # steady, spike, burst-failure
        self.target_rate = 10.0  # events per second
        self.running = False
        self.published_count = 0
        self.rejected_count = 0
        self.recent_rejections = []  # List of dicts: {"timestamp": ..., "payload": ..., "reason": ...}
        self.lock = threading.Lock()
        self.producer = None
        self.kafka_topic = os.environ.get("KAFKA_TOPIC", "clickstream-events")

    def init_producer(self):
        bootstrap_servers = os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "kafka.clickstream-pipeline.svc:9092")
        security_protocol = os.environ.get("KAFKA_SECURITY_PROTOCOL", "SASL_SSL")
        sasl_mechanism = os.environ.get("KAFKA_SASL_MECHANISM", "SCRAM-SHA-512")
        sasl_username = os.environ.get("KAFKA_SASL_USERNAME", "producer")
        sasl_password = os.environ.get("KAFKA_SASL_PASSWORD", "producer-secret")
        ssl_ca_location = os.environ.get("KAFKA_SSL_CA_LOCATION", "/etc/kafka/certs/ca.crt")

        conf = {
            'bootstrap.servers': bootstrap_servers,
            'security.protocol': security_protocol,
        }

        # If using SASL mechanisms (SCRAM, etc.)
        if "SASL" in security_protocol:
            conf.update({
                'sasl.mechanism': sasl_mechanism,
                'sasl.username': sasl_username,
                'sasl.password': sasl_password,
            })

        # SSL CA location
        if os.path.exists(ssl_ca_location):
            conf['ssl.ca.location'] = ssl_ca_location
        elif security_protocol == "SASL_SSL":
            # For local dev, allow skipping certificate verification if CA not found
            conf['ssl.endpoint.identification.algorithm'] = 'none'

        try:
            self.producer = Producer(conf)
            print(f"Kafka Producer initialized. Target: {bootstrap_servers}")
        except Exception as e:
            print(f"Failed to initialize Kafka Producer: {e}")
            self.producer = None

    def add_rejection(self, payload, reason):
        with self.lock:
            self.rejected_count += 1
            EVENTS_REJECTED.labels(reason=reason).inc()
            self.recent_rejections.insert(0, {
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "payload": payload,
                "reason": reason
            })
            # Limit list size to 10
            if len(self.recent_rejections) > 10:
                self.recent_rejections.pop()

    def generate_random_event(self, malformed=False):
        # Generates simulated clickstream event
        user_id = f"usr_{random.randint(100000, 999999)}"
        session_id = f"ses_{random.randint(10000000, 99999999)}"
        
        # User session sequences
        event_type = random.choice(["page_view", "page_view", "cart_add", "purchase", "page_exit"])
        page_urls = {
            "page_view": ["/home", "/category/electronics", "/category/books", "/product/item-xyz"],
            "cart_add": ["/product/item-xyz", "/cart"],
            "purchase": ["/checkout/success"],
            "page_exit": ["/home", "/product/item-xyz"]
        }
        
        page_url = random.choice(page_urls[event_type])
        product_id = "prod_7788" if event_type in ["cart_add", "purchase"] else None
        product_category = "electronics" if product_id else None
        price_inr = 14999.0 if product_id else None

        event = {
            "schema_version": "1.0",
            "event_id": str(uuid.uuid4()),
            "user_id": user_id,
            "session_id": session_id,
            "event_type": event_type,
            "page_url": page_url,
            "product_id": product_id,
            "product_category": product_category,
            "price_inr": price_inr,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }

        if malformed:
            # Randomly break the schema to test validation and DLQ
            fail_type = random.choice(["missing_required", "invalid_type", "invalid_enum"])
            if fail_type == "missing_required":
                event.pop("event_type", None)
            elif fail_type == "invalid_type":
                event["price_inr"] = "not-a-number"
            elif fail_type == "invalid_enum":
                event["event_type"] = "invalid_action_type"
            # Modify schema version to fail const check
            event["schema_version"] = "2.0"

        return event

    def run_loop(self):
        self.init_producer()
        
        while self.running:
            start_time = time.time()
            
            # Determine rate and malformed status based on pattern
            current_rate = self.target_rate
            malformed = False

            if self.pattern == "spike":
                # Simulate a spike (e.g. increase rate by 5x)
                current_rate = self.target_rate * 5.0
            elif self.pattern == "burst-failure":
                # Send malformed events
                malformed = True

            CURRENT_RATE.set(current_rate)

            # Generate and process event
            event = self.generate_random_event(malformed=malformed)
            
            # Internal schema validation (US-1.2)
            # If in burst-failure, we INTENTIONALLY bypass validation to publish malformed events to Kafka
            # so they hit Spark DLQ. Otherwise, we validate and reject.
            is_valid = True
            errors = []
            
            if not malformed:
                is_valid, errors = schemas.validate_event(event)
            
            if is_valid:
                # Publish to Kafka
                payload = json.dumps(event)
                if self.producer:
                    try:
                        self.producer.produce(
                            self.kafka_topic, 
                            key=event["session_id"].encode('utf-8'),
                            value=payload.encode('utf-8')
                        )
                        self.producer.poll(0)
                        self.published_count += 1
                        EVENTS_PUBLISHED.labels(event_type=event.get("event_type", "unknown")).inc()
                    except Exception as e:
                        print(f"Kafka produce error: {e}")
                else:
                    # Fallback for dry-run
                    self.published_count += 1
                    EVENTS_PUBLISHED.labels(event_type=event.get("event_type", "unknown")).inc()
            else:
                self.add_rejection(event, "; ".join(errors))

            # Sleep to maintain target rate
            elapsed = time.time() - start_time
            sleep_time = (1.0 / current_rate) - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)

        if self.producer:
            self.producer.flush()

simulator = TrafficSimulator()
simulator.init_producer()

# Helper function to check API key
def require_api_key(f):
    def decorated(*args, **kwargs):
        api_key = request.headers.get("X-API-Key")
        if not api_key or api_key != ADMIN_API_KEY:
            return jsonify({"status": "error", "message": "Unauthorized"}), 401
        return f(*args, **kwargs)
    decorated.__name__ = f.__name__
    return decorated

# Ingestion API endpoint (US-1.2 validation)
@app.route("/api/events", methods=["POST"])
@limiter.limit("10 per second")
def ingest_event():
    try:
        data = request.json
        if not data:
            return jsonify({"status": "error", "message": "Missing JSON payload"}), 400
        
        is_valid, errors = schemas.validate_event(data)
        if not is_valid:
            error_msg = "; ".join(errors)
            simulator.add_rejection(data, error_msg)
            return jsonify({"status": "error", "message": f"Schema Validation Failed: {error_msg}"}), 400

        # Publish to Kafka
        payload = json.dumps(data)
        if not simulator.producer:
            simulator.init_producer()

        if simulator.producer:
            simulator.producer.produce(
                simulator.kafka_topic,
                key=data["session_id"].encode('utf-8'),
                value=payload.encode('utf-8')
            )
            simulator.producer.flush(2)
        else:
            raise Exception("Kafka producer is not available")
        
        simulator.published_count += 1
        EVENTS_PUBLISHED.labels(event_type=data["event_type"]).inc()
        return jsonify({"status": "success", "message": "Event published"}), 201
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

# Control endpoints for Admin Panel
@app.route("/admin/config", methods=["POST"])
@require_api_key
def update_config():
    data = request.json
    if not data:
        return jsonify({"status": "error", "message": "Missing payload"}), 400

    with simulator.lock:
        if "pattern" in data:
            if data["pattern"] not in ["steady", "spike", "burst-failure"]:
                return jsonify({"status": "error", "message": "Invalid pattern"}), 400
            simulator.pattern = data["pattern"]
        if "target_rate" in data:
            try:
                simulator.target_rate = float(data["target_rate"])
            except ValueError:
                return jsonify({"status": "error", "message": "Invalid target_rate"}), 400

    return jsonify({
        "status": "success",
        "pattern": simulator.pattern,
        "target_rate": simulator.target_rate
    })

@app.route("/admin/status", methods=["GET"])
def get_status():
    with simulator.lock:
        return jsonify({
            "running": simulator.running,
            "pattern": simulator.pattern,
            "target_rate": simulator.target_rate,
            "published_count": simulator.published_count,
            "rejected_count": simulator.rejected_count,
            "recent_rejections": simulator.recent_rejections
        })

@app.route("/admin/start", methods=["POST"])
@require_api_key
def start_simulator():
    with simulator.lock:
        if not simulator.running:
            simulator.running = True
            threading.Thread(target=simulator.run_loop, daemon=True).start()
            return jsonify({"status": "success", "message": "Simulator started"})
        return jsonify({"status": "success", "message": "Simulator already running"})

@app.route("/admin/stop", methods=["POST"])
@require_api_key
def stop_simulator():
    with simulator.lock:
        if simulator.running:
            simulator.running = False
            return jsonify({"status": "success", "message": "Simulator stopped"})
        return jsonify({"status": "success", "message": "Simulator not running"})

# Prometheus metrics route
@app.route("/metrics", methods=["GET"])
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}

# Admin Panel UI
@app.route("/", methods=["GET"])
def index():
    # Render a premium, styled admin dashboard html template directly
    html_template = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>K.S.C.E.P. Producer Admin Panel</title>
        <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;700&display=swap" rel="stylesheet">
        <style>
            :root {
                --bg-primary: #0a0e17;
                --bg-secondary: #121824;
                --accent-blue: #0070f3;
                --accent-green: #1e7b34;
                --accent-amber: #bf8f00;
                --accent-red: #c00000;
                --text-main: #f5f6f8;
                --text-muted: #8a94a6;
                --border-color: #222e45;
            }

            * {
                box-sizing: border-box;
                margin: 0;
                padding: 0;
            }

            body {
                font-family: 'Outfit', sans-serif;
                background-color: var(--bg-primary);
                color: var(--text-main);
                min-height: 100vh;
                padding: 2rem;
            }

            .container {
                max-width: 1100px;
                margin: 0 auto;
            }

            header {
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-bottom: 2rem;
                border-bottom: 1px solid var(--border-color);
                padding-bottom: 1.5rem;
            }

            h1 {
                font-weight: 700;
                font-size: 2rem;
                background: linear-gradient(135deg, #0070f3, #00dfd8);
                -webkit-background-clip: text;
                -webkit-text-fill-color: transparent;
            }

            .badge {
                padding: 0.5rem 1rem;
                border-radius: 9999px;
                font-weight: 600;
                font-size: 0.85rem;
                text-transform: uppercase;
                letter-spacing: 0.05em;
            }

            .badge-active {
                background-color: rgba(30, 123, 52, 0.2);
                color: #2ebd59;
                border: 1px solid #1e7b34;
            }

            .badge-inactive {
                background-color: rgba(192, 0, 0, 0.2);
                color: #ff4d4d;
                border: 1px solid #c00000;
            }

            .grid {
                display: grid;
                grid-template-columns: 1fr 1fr;
                gap: 2rem;
                margin-bottom: 2rem;
            }

            @media (max-width: 768px) {
                .grid {
                    grid-template-columns: 1fr;
                }
            }

            .card {
                background-color: var(--bg-secondary);
                border: 1px solid var(--border-color);
                border-radius: 12px;
                padding: 1.5rem;
                box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.3);
            }

            .card-title {
                font-size: 1.25rem;
                font-weight: 600;
                margin-bottom: 1.5rem;
                border-bottom: 1px solid var(--border-color);
                padding-bottom: 0.5rem;
            }

            .form-group {
                margin-bottom: 1.25rem;
            }

            label {
                display: block;
                font-size: 0.9rem;
                color: var(--text-muted);
                margin-bottom: 0.5rem;
                font-weight: 500;
            }

            input[type="text"], input[type="password"], select {
                width: 100%;
                background-color: var(--bg-primary);
                border: 1px solid var(--border-color);
                padding: 0.75rem;
                border-radius: 6px;
                color: var(--text-main);
                font-family: inherit;
                font-size: 1rem;
                transition: border-color 0.2s;
            }

            input[type="text"]:focus, input[type="password"]:focus, select:focus {
                border-color: var(--accent-blue);
                outline: none;
            }

            .slider-container {
                display: flex;
                align-items: center;
                gap: 1rem;
            }

            input[type="range"] {
                flex-grow: 1;
                accent-color: var(--accent-blue);
            }

            .rate-val {
                font-weight: 700;
                font-size: 1.1rem;
                min-width: 3.5rem;
                text-align: right;
            }

            .btn {
                width: 100%;
                background-color: var(--accent-blue);
                color: var(--text-main);
                border: none;
                padding: 0.75rem;
                font-size: 1rem;
                font-weight: 600;
                border-radius: 6px;
                cursor: pointer;
                transition: background-color 0.2s, transform 0.1s;
                font-family: inherit;
            }

            .btn:hover {
                background-color: #0060d3;
            }

            .btn:active {
                transform: scale(0.98);
            }

            .btn-danger {
                background-color: var(--accent-red);
            }
            .btn-danger:hover {
                background-color: #a00000;
            }

            .btn-success {
                background-color: var(--accent-green);
            }
            .btn-success:hover {
                background-color: #176028;
            }

            .btn-stop {
                background-color: #595959;
            }
            .btn-stop:hover {
                background-color: #404040;
            }

            .stats-container {
                display: grid;
                grid-template-columns: 1fr 1fr;
                gap: 1rem;
            }

            .stat-box {
                background-color: var(--bg-primary);
                border: 1px solid var(--border-color);
                border-radius: 8px;
                padding: 1rem;
                text-align: center;
            }

            .stat-val {
                font-size: 1.75rem;
                font-weight: 700;
                margin-top: 0.25rem;
            }

            .stat-val-published {
                color: #2ebd59;
            }

            .stat-val-rejected {
                color: #ff4d4d;
            }

            .rejection-item {
                background-color: var(--bg-primary);
                border: 1px solid var(--border-color);
                border-radius: 6px;
                padding: 0.75rem;
                margin-bottom: 0.75rem;
                font-size: 0.85rem;
            }

            .rejection-meta {
                display: flex;
                justify-content: space-between;
                color: var(--text-muted);
                margin-bottom: 0.4rem;
                font-weight: 600;
            }

            .rejection-reason {
                color: #ff4d4d;
                font-weight: 500;
                margin-bottom: 0.4rem;
            }

            pre {
                background-color: rgba(0,0,0,0.3);
                padding: 0.5rem;
                border-radius: 4px;
                overflow-x: auto;
                font-family: monospace;
            }

            /* Modal Styles */
            .modal {
                display: none;
                position: fixed;
                top: 0; left: 0; width: 100%; height: 100%;
                background-color: rgba(0,0,0,0.8);
                z-index: 1000;
                justify-content: center;
                align-items: center;
            }

            .modal-content {
                background-color: var(--bg-secondary);
                border: 1px solid var(--border-color);
                border-radius: 12px;
                padding: 2rem;
                max-width: 450px;
                width: 90%;
                text-align: center;
            }

            .modal-content h3 {
                color: var(--accent-red);
                margin-bottom: 1rem;
            }

            .modal-content p {
                color: var(--text-muted);
                margin-bottom: 1.5rem;
                line-height: 1.4;
            }

            .modal-actions {
                display: flex;
                gap: 1rem;
            }

            #toast {
                position: fixed;
                bottom: 2rem;
                right: 2rem;
                background-color: var(--accent-blue);
                color: white;
                padding: 1rem 1.5rem;
                border-radius: 6px;
                box-shadow: 0 4px 12px rgba(0,0,0,0.5);
                font-weight: 600;
                opacity: 0;
                transition: opacity 0.3s;
                pointer-events: none;
                z-index: 2000;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <header>
                <div>
                    <h1>K.S.C.E.P. Traffic Control</h1>
                    <p style="color: var(--text-muted); font-size: 0.9rem; margin-top: 0.25rem;">Real-Time Clickstream Simulator</p>
                </div>
                <div id="sim-status-badge" class="badge badge-inactive">Simulator Stopped</div>
            </header>

            <div class="grid">
                <!-- Left: Controls -->
                <div class="card">
                    <h2 class="card-title">Simulator Settings</h2>
                    
                    <div class="form-group">
                        <label for="api-key-input">API Key (Required for Changes)</label>
                        <input type="password" id="api-key-input" placeholder="Enter API Key">
                    </div>

                    <div class="form-group">
                        <label for="pattern-select">Traffic Pattern</label>
                        <select id="pattern-select">
                            <option value="steady">Steady Flow</option>
                            <option value="spike">Spike Mode (5x Target Rate)</option>
                            <option value="burst-failure">Burst-Failure Mode (Send Malformed Events)</option>
                        </select>
                    </div>

                    <div class="form-group">
                        <label for="rate-slider">Target Rate (events/sec)</label>
                        <div class="slider-container">
                            <input type="range" id="rate-slider" min="1" max="100" value="10">
                            <span class="rate-val"><span id="rate-val-text">10</span>/s</span>
                        </div>
                    </div>

                    <div class="form-group" style="margin-top: 2rem; display: flex; gap: 1rem;">
                        <button id="btn-start" class="btn btn-success">Start Simulator</button>
                        <button id="btn-stop" class="btn btn-stop" style="display:none;">Stop Simulator</button>
                        <button id="btn-apply" class="btn">Apply Changes</button>
                    </div>
                </div>

                <!-- Right: Stats -->
                <div class="card">
                    <h2 class="card-title">Live Pipeline Counters</h2>
                    
                    <div class="stats-container" style="margin-bottom: 2rem;">
                        <div class="stat-box">
                            <label>Published (Kafka)</label>
                            <div id="stat-published" class="stat-val stat-val-published">0</div>
                        </div>
                        <div class="stat-box">
                            <label>Rejected (Validation)</label>
                            <div id="stat-rejected" class="stat-val stat-val-rejected">0</div>
                        </div>
                    </div>

                    <div class="stat-box" style="width: 100%;">
                        <label>Current Generating Rate</label>
                        <div id="stat-current-rate" class="stat-val" style="color: var(--accent-blue);">0/s</div>
                    </div>
                </div>
            </div>

            <!-- Recent Schema Rejections -->
            <div class="card">
                <h2 class="card-title">Recent Schema Rejections (Last 10)</h2>
                <div id="rejections-list">
                    <p style="color: var(--text-muted); text-align: center; padding: 1rem;">No schema rejections recorded yet.</p>
                </div>
            </div>
        </div>

        <!-- Confirmation Modal for Burst Failure -->
        <div id="confirm-modal" class="modal">
            <div class="modal-content">
                <h3>Warning: Burst-Failure Pattern</h3>
                <p>This action will intentionally generate and publish malformed events directly into your Kafka stream to test the DLQ and error handling layers. Do you wish to continue?</p>
                <div class="modal-actions">
                    <button id="modal-cancel" class="btn btn-stop">Cancel</button>
                    <button id="modal-confirm" class="btn btn-danger">Yes, Continue</button>
                </div>
            </div>
        </div>

        <div id="toast">Changes Applied!</div>

        <script>
            let currentPattern = 'steady';
            let simulatorRunning = false;

            // Load saved key from memory (session)
            let apiKey = '';

            const apiKeyInput = document.getElementById('api-key-input');
            const patternSelect = document.getElementById('pattern-select');
            const rateSlider = document.getElementById('rate-slider');
            const rateValText = document.getElementById('rate-val-text');
            const btnApply = document.getElementById('btn-apply');
            const btnStart = document.getElementById('btn-start');
            const btnStop = document.getElementById('btn-stop');
            const confirmModal = document.getElementById('confirm-modal');
            const modalCancel = document.getElementById('modal-cancel');
            const modalConfirm = document.getElementById('modal-confirm');
            const toast = document.getElementById('toast');

            rateSlider.addEventListener('input', () => {
                rateValText.innerText = rateSlider.value;
            });

            function showToast(message, isError = false) {
                toast.innerText = message;
                toast.style.backgroundColor = isError ? 'var(--accent-red)' : 'var(--accent-blue)';
                toast.style.opacity = '1';
                setTimeout(() => {
                    toast.style.opacity = '0';
                }, 3000);
            }

            async function updateStatus() {
                try {
                    const res = await fetch('/admin/status');
                    const data = await res.json();
                    
                    simulatorRunning = data.running;
                    document.getElementById('stat-published').innerText = data.published_count;
                    document.getElementById('stat-rejected').innerText = data.rejected_count;
                    document.getElementById('stat-current-rate').innerText = (data.running ? data.target_rate : 0) + '/s';

                    const badge = document.getElementById('sim-status-badge');
                    if (data.running) {
                        badge.innerText = `Active - ${data.pattern}`;
                        badge.className = 'badge badge-active';
                        btnStart.style.display = 'none';
                        btnStop.style.display = 'block';
                    } else {
                        badge.innerText = 'Simulator Stopped';
                        badge.className = 'badge badge-inactive';
                        btnStart.style.display = 'block';
                        btnStop.style.display = 'none';
                    }

                    // Update rejections
                    const rejectionsList = document.getElementById('rejections-list');
                    if (data.recent_rejections.length === 0) {
                        rejectionsList.innerHTML = '<p style="color: var(--text-muted); text-align: center; padding: 1rem;">No schema rejections recorded yet.</p>';
                    } else {
                        rejectionsList.innerHTML = data.recent_rejections.map(r => `
                            <div class="rejection-item">
                                <div class="rejection-meta">
                                    <span>${r.timestamp}</span>
                                </div>
                                <div class="rejection-reason">${r.reason}</div>
                                <pre>${JSON.stringify(r.payload, null, 2)}</pre>
                            </div>
                        `).join('');
                    }
                } catch (e) {
                    console.error("Failed to fetch status", e);
                }
            }

            async function postAction(url, body = {}) {
                apiKey = apiKeyInput.value;
                try {
                    const res = await fetch(url, {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                            'X-API-Key': apiKey
                        },
                        body: JSON.stringify(body)
                    });
                    const data = await res.json();
                    if (res.status === 401) {
                        showToast("Unauthorized: Invalid API Key", true);
                        return false;
                    }
                    if (data.status === 'error') {
                        showToast("Error: " + data.message, true);
                        return false;
                    }
                    return data;
                } catch (e) {
                    showToast("Network Error", true);
                    return false;
                }
            }

            btnApply.addEventListener('click', async () => {
                const targetPattern = patternSelect.value;
                if (targetPattern === 'burst-failure' && currentPattern !== 'burst-failure') {
                    confirmModal.style.display = 'flex';
                } else {
                    await applyConfig();
                }
            });

            modalCancel.addEventListener('click', () => {
                confirmModal.style.display = 'none';
                patternSelect.value = currentPattern;
            });

            modalConfirm.addEventListener('click', async () => {
                confirmModal.style.display = 'none';
                await applyConfig();
            });

            async function applyConfig() {
                const pattern = patternSelect.value;
                const rate = rateSlider.value;
                const result = await postAction('/admin/config', {
                    pattern: pattern,
                    target_rate: parseFloat(rate)
                });
                if (result) {
                    currentPattern = pattern;
                    showToast("Configuration Applied!");
                    updateStatus();
                }
            }

            btnStart.addEventListener('click', async () => {
                const result = await postAction('/admin/start');
                if (result) {
                    showToast("Simulator Started!");
                    updateStatus();
                }
            });

            btnStop.addEventListener('click', async () => {
                const result = await postAction('/admin/stop');
                if (result) {
                    showToast("Simulator Stopped!");
                    updateStatus();
                }
            });

            // Poll status every 2 seconds
            setInterval(updateStatus, 2000);
            updateStatus();
        </script>
    </body>
    </html>
    """
    return render_template_string(html_template)

if __name__ == "__main__":
    # In docker environment, the app runs on port 8080
    app.run(host="0.0.0.0", port=8080)
