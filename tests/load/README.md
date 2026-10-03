# K.S.C.E.P. Platform Load Testing Suite

This suite uses [Locust](https://locust.io/) to simulate realistic user clickstream traffic and evaluate Kafka queue backpressure and KEDA autoscaling response.

## Running Locally

1. Install dependencies:
   ```bash
   pip install -r tests/load/requirements.txt
   ```

2. Start the Locust load test (Web UI at http://localhost:8089):
   ```bash
   locust -f tests/load/locustfile.py --host http://localhost:5000
   ```

3. Headless execution:
   ```bash
   locust -f tests/load/locustfile.py --headless -u 100 -r 10 --run-time 2m --host http://localhost:5000
   ```

## Running Inside Kubernetes Cluster

Apply the Locust Kubernetes Job to run traffic generation directly against the producer pod:

```bash
kubectl apply -f tests/load/k8s-locust-job.yaml
kubectl logs -n clickstream-pipeline -l app=locust-load-test -f
```
