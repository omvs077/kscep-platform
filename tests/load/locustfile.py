import os
import uuid
import random
from datetime import datetime, timezone
from locust import HttpUser, task, between, events

CATEGORIES = ["Electronics", "Footwear", "Apparel", "Books", "Home & Kitchen", "Fitness"]
PAGES = [
    "/",
    "/products/laptops",
    "/products/smartphones",
    "/products/headphones",
    "/categories/fashion",
    "/categories/footwear/running-shoes",
    "/cart",
    "/checkout"
]

class ClickstreamUser(HttpUser):
    wait_time = between(0.05, 0.5)

    def on_start(self):
        self.user_id = f"user_{uuid.uuid4().hex[:12]}"
        self.session_id = str(uuid.uuid4())
        self.api_key = os.environ.get("ADMIN_API_KEY", "default-dev-key")
        self.headers = {
            "Content-Type": "application/json",
            "X-API-Key": self.api_key
        }

    def _generate_event(self, event_type: str, page_url: str = None, malformed: bool = False) -> dict:
        if malformed:
            return {
                "schema_version": "99.0",
                "invalid_field": True,
                "timestamp": datetime.now(timezone.utc).isoformat()
            }

        product_id = None
        category = None
        price = None

        if event_type in ("cart_add", "purchase") or "products" in (page_url or ""):
            product_id = f"prod_{random.randint(100, 999)}"
            category = random.choice(CATEGORIES)
            price = round(random.uniform(99.0, 99999.0), 2)

        return {
            "schema_version": "1.0",
            "event_id": str(uuid.uuid4()),
            "user_id": self.user_id,
            "session_id": self.session_id,
            "event_type": event_type,
            "page_url": page_url or random.choice(PAGES),
            "product_id": product_id,
            "product_category": category,
            "price_inr": price,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }

    @task(6)
    def browse_page(self):
        page = random.choice(PAGES)
        payload = self._generate_event("page_view", page_url=page)
        with self.client.post("/api/events", json=payload, headers=self.headers, catch_response=True) as resp:
            if resp.status_code in (200, 201, 202):
                resp.success()
            else:
                resp.failure(f"Unexpected status: {resp.status_code} - {resp.text}")

    @task(3)
    def add_to_cart(self):
        page = f"/products/item-{random.randint(100, 999)}"
        payload = self._generate_event("cart_add", page_url=page)
        with self.client.post("/api/events", json=payload, headers=self.headers, catch_response=True) as resp:
            if resp.status_code in (200, 201, 202):
                resp.success()
            else:
                resp.failure(f"Unexpected status: {resp.status_code} - {resp.text}")

    @task(1)
    def make_purchase(self):
        payload = self._generate_event("purchase", page_url="/checkout/success")
        with self.client.post("/api/events", json=payload, headers=self.headers, catch_response=True) as resp:
            if resp.status_code in (200, 201, 202):
                resp.success()
            else:
                resp.failure(f"Unexpected status: {resp.status_code} - {resp.text}")

    @task(1)
    def page_exit(self):
        payload = self._generate_event("page_exit", page_url="/")
        with self.client.post("/api/events", json=payload, headers=self.headers, catch_response=True) as resp:
            if resp.status_code in (200, 201, 202):
                resp.success()
            else:
                resp.failure(f"Unexpected status: {resp.status_code} - {resp.text}")
        # Reset session after exit
        self.session_id = str(uuid.uuid4())
