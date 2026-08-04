# DCO Resource Optimization Strategy
## FinOps Methodology & Thesis Documentation Template

---

## 1. Executive Summary

This document presents a structured, data-driven methodology for optimizing AWS cloud resource allocation in the DevOps-Enabled Cloud Resource Optimizer (DCO) system. By correlating CloudWatch metrics collected during controlled load tests against idle baselines, we scientifically justify right-sizing EC2 instances to reduce cloud costs while maintaining service-level objectives (SLOs).

---

## 2. Optimization Framework Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                  DCO FinOps Optimization Cycle                   │
│                                                                  │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐  │
│   │ MEASURE  │───▶│ ANALYZE  │───▶│ OPTIMIZE │───▶│ VALIDATE │  │
│   │          │    │          │    │          │    │          │  │
│   │ Collect  │    │ Compare  │    │ Right-   │    │ Re-test  │  │
│   │ Baseline │    │ Idle vs  │    │ size or  │    │ & verify │  │
│   │ & Load   │    │ Load     │    │ scale    │    │ SLOs met │  │
│   └──────────┘    └──────────┘    └──────────┘    └──────────┘  │
│        ▲                                               │        │
│        └───────────────────────────────────────────────┘        │
│                      Continuous Loop                             │
└──────────────────────────────────────────────────────────────────┘
```

---

## 3. Phase A: Baseline Measurement (Idle State)

### 3.1 Objective
Establish the resource consumption profile of the application when no user traffic is present. This defines the **minimum viable resource requirement**.

### 3.2 Procedure

| Step | Action | Duration |
|------|--------|----------|
| 1 | Deploy the DCO API on the target instance (e.g., `t3.medium`) | — |
| 2 | Ensure CloudWatch Agent is running and publishing to `DCO_Project_Metrics` | — |
| 3 | Let the system idle with **zero user traffic** | 30–60 minutes |
| 4 | Record baseline metrics from the CloudWatch Dashboard | — |

### 3.3 Metrics to Record

| Metric | Source | Expected Idle Range |
|--------|--------|-------------------|
| CPU Utilization (%) | `cpu_usage_user` + `cpu_usage_system` | 0.5% – 3% |
| Memory Utilization (%) | `mem_used_percent` | 15% – 35% |
| Memory Used (MB) | `mem_used` | 150 – 350 MB |
| Disk I/O (bytes/sec) | `diskio_read_bytes`, `diskio_write_bytes` | Near zero |
| Network I/O (bytes/sec) | `net_bytes_sent`, `net_bytes_recv` | < 1 KB/s |
| CPU Credit Balance | `CPUCreditBalance` (AWS/EC2) | Stable / accumulating |

### 3.4 Documentation Template

```
BASELINE MEASUREMENT REPORT
============================
Date:               _______________
Instance Type:      t3.medium (2 vCPU, 4 GB RAM)
Measurement Window: [HH:MM] to [HH:MM] UTC (XX minutes)
Traffic:            Zero (idle)

Results:
  CPU Utilization:     Avg ___%, Max ___%
  Memory Utilization:  Avg ___%, Max ___%
  Memory Used:         Avg ___ MB
  Disk Used:           ___%
  Network In/Out:      ___ / ___ bytes/sec

Observation:
  [Describe what you observe — e.g., "The system uses only 2% CPU and
   22% memory at idle, indicating significant over-provisioning."]
```

---

## 4. Phase B: Load Test Measurement (Stressed State)

### 4.1 Objective
Determine the **peak resource consumption** under realistic and extreme load conditions using the Locust load testing framework.

### 4.2 Test Scenarios

| Scenario | Locust Users | Duration | Purpose |
|----------|-------------|----------|---------|
| **Light Load** | 10 users, ramp 2/s | 5 min | Normal production traffic simulation |
| **Medium Load** | 30 users, ramp 5/s | 5 min | Growth scenario / moderate spike |
| **Heavy Load** | 50 users, ramp 10/s | 5 min | Peak traffic / promotional event |
| **Stress Test** | 100 users, ramp 10/s | 10 min | Break-point analysis |

### 4.3 Locust Commands

```bash
# Light Load
locust -f locustfile.py --host http://<EC2_IP> \
  --headless -u 10 -r 2 --run-time 5m --csv results/light

# Medium Load
locust -f locustfile.py --host http://<EC2_IP> \
  --headless -u 30 -r 5 --run-time 5m --csv results/medium

# Heavy Load
locust -f locustfile.py --host http://<EC2_IP> \
  --headless -u 50 -r 10 --run-time 5m --csv results/heavy

# Stress Test (Break-point)
locust -f locustfile.py --host http://<EC2_IP> \
  --headless -u 100 -r 10 --run-time 10m --csv results/stress
```

### 4.4 Metrics to Record (Per Scenario)

| Metric | Light | Medium | Heavy | Stress |
|--------|-------|--------|-------|--------|
| CPU Avg (%) | ___ | ___ | ___ | ___ |
| CPU Max (%) | ___ | ___ | ___ | ___ |
| Memory Avg (%) | ___ | ___ | ___ | ___ |
| Memory Max (%) | ___ | ___ | ___ | ___ |
| Response Time P50 (ms) | ___ | ___ | ___ | ___ |
| Response Time P95 (ms) | ___ | ___ | ___ | ___ |
| Response Time P99 (ms) | ___ | ___ | ___ | ___ |
| Error Rate (%) | ___ | ___ | ___ | ___ |
| Requests/sec | ___ | ___ | ___ | ___ |
| CPU Credits Consumed | ___ | ___ | ___ | ___ |

### 4.5 Documentation Template

```
LOAD TEST MEASUREMENT REPORT
==============================
Date:               _______________
Instance Type:      t3.medium (2 vCPU, 4 GB RAM)
Scenario:           [Light / Medium / Heavy / Stress]
Locust Config:      -u ___ -r ___ --run-time ___
Measurement Window: [HH:MM] to [HH:MM] UTC

Server Metrics (CloudWatch):
  CPU Utilization:     Avg ___%, Max ___%, Min ___%
  Memory Utilization:  Avg ___%, Max ___%, Min ___%
  CPU Credits:         Start ___, End ___, Consumed ___

Client Metrics (Locust):
  Total Requests:      ___
  Requests/sec:        ___
  Response Time:       P50 ___ms, P95 ___ms, P99 ___ms
  Error Rate:          ___%
  Failures:            ___

Observation:
  [Describe the findings — e.g., "Under heavy load (50 users), CPU peaked
   at 72% and memory at 45%. The instance maintained <200ms P95 response
   times with 0% error rate, indicating headroom for downsizing."]
```

---

## 5. Phase C: Comparative Analysis & Right-Sizing Decision

### 5.1 Analysis Matrix

Fill this table with data from Phases A and B:

| Metric | Idle (Baseline) | Light (10u) | Medium (30u) | Heavy (50u) | Stress (100u) |
|--------|----------------|-------------|---------------|-------------|----------------|
| CPU Avg % | ___ | ___ | ___ | ___ | ___ |
| CPU Max % | ___ | ___ | ___ | ___ | ___ |
| Memory Avg % | ___ | ___ | ___ | ___ | ___ |
| Memory Max % | ___ | ___ | ___ | ___ | ___ |
| P95 Latency (ms) | ___ | ___ | ___ | ___ | ___ |
| Error Rate % | 0 | ___ | ___ | ___ | ___ |
| CPU Credits Used | 0 | ___ | ___ | ___ | ___ |

### 5.2 Right-Sizing Decision Framework

```
IF   CPU_Max_Under_Heavy_Load < 70%
AND  Memory_Max_Under_Heavy_Load < 70%
AND  P95_Latency < SLO_Target (e.g., 500ms)
AND  Error_Rate < 1%
THEN → Instance is OVER-PROVISIONED → Recommend DOWNSIZE

IF   CPU_Max_Under_Medium_Load > 80%
OR   Memory_Max_Under_Medium_Load > 85%
OR   P95_Latency > SLO_Target
OR   Error_Rate > 5%
THEN → Instance is UNDER-PROVISIONED → Recommend UPSIZE

OTHERWISE → Instance is RIGHT-SIZED → No change needed
```

### 5.3 Instance Comparison Table

| Property | Current: t3.medium | Proposed: t3.micro | Savings |
|----------|-------------------|-------------------|---------|
| vCPUs | 2 | 2 | — |
| RAM | 4 GB | 1 GB | -75% |
| On-Demand Price (us-east-1) | $0.0416/hr | $0.0104/hr | **-75%** |
| Monthly Cost (730 hrs) | $30.37 | $7.59 | **$22.78/mo** |
| Annual Cost | $364.40 | $91.10 | **$273.30/yr** |
| CPU Baseline Credits/hr | 24 | 12 | -50% |
| Network Bandwidth | Up to 5 Gbps | Up to 5 Gbps | — |

### 5.4 Cost Savings Calculation Formula

```
Monthly Savings = (Current_Hourly_Rate - Proposed_Hourly_Rate) × 730 hours

Annual Savings  = Monthly_Savings × 12

Savings Percentage = ((Current - Proposed) / Current) × 100

ROI of Optimization = (Annual_Savings / Cost_of_Optimization_Effort) × 100
```

---

## 6. Phase D: Validation (Post-Optimization)

### 6.1 Procedure

| Step | Action |
|------|--------|
| 1 | Change instance type to the recommended size (e.g., `t3.micro`) |
| 2 | Redeploy the application and CloudWatch Agent |
| 3 | Repeat the **exact same load test scenarios** from Phase B |
| 4 | Compare results to confirm SLOs are still met |

### 6.2 Validation Criteria

| Criterion | SLO Target | Post-Optimization Result | Pass/Fail |
|-----------|-----------|-------------------------|-----------|
| Health check availability | 99.9% | ___% | ☐ |
| P95 Response Time (light) | < 200ms | ___ms | ☐ |
| P95 Response Time (heavy) | < 500ms | ___ms | ☐ |
| Error Rate (heavy) | < 1% | ___% | ☐ |
| CPU Max (heavy) | < 85% | ___% | ☐ |
| Memory Max (heavy) | < 90% | ___% | ☐ |

### 6.3 Conclusion Template

```
OPTIMIZATION VALIDATION REPORT
================================
Original Instance:    t3.medium ($30.37/mo)
Optimized Instance:   t3.micro  ($7.59/mo)
Monthly Savings:      $22.78 (75%)
Annual Savings:       $273.30

SLO Compliance:       [All passed / X of Y passed]

Conclusion:
  [Based on the empirical evidence collected through controlled load
   testing and CloudWatch metric analysis, the DCO system demonstrates
   that the application workload can be served by a t3.micro instance
   without violating any defined service-level objectives. This
   right-sizing decision yields a 75% reduction in compute costs,
   validating the effectiveness of the DevOps-Enabled Cloud Resource
   Optimizer methodology.]
```

---

## 7. Thesis Chapter Structure Recommendation

For your capstone thesis, structure the optimization chapter as follows:

```
Chapter X: Cloud Resource Optimization

  X.1  Introduction to FinOps and Cloud Cost Optimization
       - Define FinOps principles (Inform, Optimize, Operate)
       - Explain the importance of right-sizing

  X.2  Experimental Setup
       - Instance specifications (before optimization)
       - CloudWatch Agent configuration
       - Load testing tool and methodology (Locust)
       - Defined SLOs

  X.3  Baseline Measurement (Idle State)
       - Data collection procedure
       - Results table and CloudWatch screenshots
       - Analysis: resource utilization at rest

  X.4  Load Test Experiments
       - Scenario definitions (Light / Medium / Heavy / Stress)
       - Results tables (fill in the templates above)
       - CloudWatch Dashboard screenshots (annotated)
       - Locust report charts (RPS, response times, error rates)

  X.5  Comparative Analysis
       - Idle vs. Load utilization comparison
       - Identification of over-provisioning
       - Right-sizing decision using the decision framework

  X.6  Cost Analysis
       - Current vs. Proposed cost breakdown
       - Annual savings projection
       - ROI calculation

  X.7  Validation
       - Post-optimization load test results
       - SLO compliance verification
       - Before/After comparison table

  X.8  Conclusion
       - Summary of findings
       - Quantified cost savings
       - Recommendations for production deployments
       - Limitations and future work
```

---

## 8. Key Metrics Interpretation Guide

### How to Read CloudWatch During Idle vs. Load

| Observation | What It Means | Action |
|---|---|---|
| CPU idle: 2%, load: 35% | Instance has **~65% headroom** even under load | Strong candidate for downsizing |
| CPU idle: 2%, load: 92% | Instance is **fully utilized** under load | Do NOT downsize; consider upsizing |
| Memory idle: 20%, load: 45% | Memory has **~55% headroom** | Can reduce RAM (smaller instance) |
| Memory idle: 20%, load: 88% | Memory is **near saturation** | Cannot reduce RAM safely |
| CPU Credits depleting rapidly | T-series instance bursting beyond baseline | Workload is bursty; credits will exhaust |
| CPU Credits stable/growing | Workload is within baseline allocation | Instance is appropriately sized or oversized |
| P95 latency spike during load | Application is struggling under pressure | May need more resources or code optimization |
| High `cpu_usage_steal` | Hypervisor is throttling your instance | Upgrade to a dedicated/larger instance |
| High `cpu_usage_iowait` | Disk is the bottleneck, not CPU | Upgrade EBS volume type (gp3 → io2) |

### The "70% Rule" for Right-Sizing

> **Best Practice**: Target **70% average utilization** under expected peak load.
> This provides a 30% safety margin for unexpected traffic spikes while
> avoiding wasteful over-provisioning.

```
Optimal Instance = Instance where Peak_Load_CPU ≈ 60-70%
                   AND Peak_Load_Memory ≈ 60-70%
                   AND SLOs are met
```

---

## 9. Advanced Optimization Strategies (Future Work)

| Strategy | Description | Estimated Additional Savings |
|----------|-------------|------------------------------|
| **Reserved Instances** | Commit to 1-year term for the optimized instance | 30–40% |
| **Spot Instances** | Use for non-critical/batch workloads | 60–90% |
| **Savings Plans** | Flexible commitment across instance families | 20–30% |
| **Auto Scaling** | Scale out during peaks, scale in during off-hours | 40–60% |
| **Scheduled Scaling** | Stop dev instances nights/weekends | 65% (non-prod) |
| **Graviton (ARM)** | Switch to `t4g.micro` for better price/performance | 20% |
