# ZGitea Installer v10
## Sovereign, Zero-Trust, Autonomous CI/CD Platform

---

## 🧠 SYSTEM IDENTITY

ZGitea v10 is a **self-orchestrating, zero-trust CI platform** designed to operate:
- Without vendor lock-in
- With deterministic, reproducible execution
- Across multi-region distributed infrastructure
- With autonomous decision-making (AI scheduler)

It merges:
- Git hosting (Gitea)
- Distributed queue (Redis Streams / CRDT model)
- Consensus (etcd / Raft)
- Execution sandbox (WASM + container fallback)
- Secure artifact pipeline (S3/MinIO + encryption)
- Service mesh (SPIFFE / mTLS)
- Edge routing (QUIC / Cloudflare)
- Build system (Bazel Remote Execution)
- Predictive orchestration (AI scheduler)

---

## 🏗️ ARCHITECTURE (LAYERED MODEL)

### 1. 🌐 Edge Layer
- Cloudflare Tunnel (QUIC)
- Latency-aware routing
- Region ingress control

**Responsibilities:**
- Terminate external traffic
- Route to nearest healthy region
- Enforce TLS + Zero Trust

---

### 2. 🔐 Identity & Trust Layer
- SPIFFE / SPIRE
- mTLS between all services

**Principles:**
- No service trusts network identity
- All identity is cryptographic
- Zero implicit trust

---

### 3. 🧭 Control Plane
- etcd (Raft consensus)
- Distributed scheduler
- AI orchestration engine

**Responsibilities:**
- Leader election
- Global state coordination
- Scaling decisions
- Failover control

---

### 4. 📦 Data Plane

#### Queue System
- Redis Streams (local)
- CRDT-inspired global replication

#### Artifact Storage
- S3 / MinIO
- Presigned URLs
- AES-256 encryption (client-side)

#### Cache Layer
- Content-addressable storage (SHA256)
- Remote cache (Bazel-compatible)

---

### 5. ⚙️ Execution Layer

#### Primary:
- WASM runtime (Wasmtime / WASI)

#### Fallback:
- Container runner (Docker + gVisor)

#### Isolation:
- Per-job sandbox
- Read-only root FS
- tmpfs workspace
- No network (or restricted CNI)

---

### 6. 🤖 Intelligence Layer

#### AI Scheduler
- Predictive scaling
- Load-aware orchestration
- Failure pattern detection

#### Capabilities:
- Scale workers dynamically
- Route jobs by latency + load
- Pre-warm execution nodes

---

## 🔁 JOB LIFECYCLE

```text
1. Developer push → Gitea
2. Webhook triggered (HMAC signed)
3. Edge receives → validates → forwards
4. Job enters Global Queue (Redis Streams / CRDT)
5. Scheduler assigns region + node
6. Worker consumes job (XREADGROUP)
7. Ephemeral runner spawned:
   - WASM (preferred)
   - Container (fallback)
8. Execution:
   - sandboxed
   - no persistence
9. Artifact:
   - encrypted
   - uploaded via presigned URL
10. Status callback → Gitea
11. Runner destroyed
```

---

## 🔐 SECURITY MODEL

### Secrets

* Stored in tmpfs (`/run/...`)
* Never persisted to disk
* Rotated automatically

### Execution Isolation

* WASM sandbox (no syscalls)
* gVisor fallback
* seccomp profiles
* network isolation

### Transport Security

* mTLS (SPIFFE)
* HMAC webhook validation

### Supply Chain

* Immutable builds
* content-addressable cache
* reproducible execution

---

## 🌍 GLOBAL DISTRIBUTION

### Multi-Region

* Regions: AP, US, EU (configurable)
* Each region runs:

  * queue shard
  * workers
  * scheduler node

### Replication

* CRDT-style eventual consistency
* Job sharding by hash
* Conflict-free merging

### Failover

* Region health monitored
* Jobs re-claimed via:

  * XAUTOCLAIM (Redis Streams)
* DLQ for failures

---

## ⚡ SCALING MODEL

### Horizontal Scaling

* Workers scale per queue depth
* Autoscaler per node

### Predictive Scaling (AI)

* Uses:

  * CPU load
  * queue latency
  * historical trends

### Strategy

* Scale up before congestion
* Scale down during idle

---

## 🧠 AI SCHEDULER DESIGN

### Inputs

* Queue length
* CPU / memory
* Job duration history
* Region latency

### Outputs

* Worker count
* Job routing decision
* Pre-warm signals

### Modes

* Reactive (threshold-based)
* Predictive (trend-based)

---

## 🧪 BUILD SYSTEM (BAZEL REMOTE EXECUTION)

### Features

* Remote execution API (REAPI)
* Distributed cache
* Deterministic builds

### Benefits

* Deduplicated builds
* Faster CI pipelines
* Reproducibility

---

## 🎯 DESIGN PRINCIPLES

### 1. Zero Trust

Nothing is trusted by default.

### 2. Ephemerality

Everything is disposable.

### 3. Determinism

Same input → same output.

### 4. Sovereignty

No dependency on external SaaS.

### 5. Observability

Everything measurable.

---

## 📊 COMPONENT SUMMARY

| Layer     | Technology      |
| --------- | --------------- |
| Edge      | Cloudflare QUIC |
| Identity  | SPIFFE/SPIRE    |
| Control   | etcd            |
| Queue     | Redis Streams   |
| Execution | WASM / Docker   |
| Cache     | S3 / MinIO      |
| Scheduler | AI Engine       |
| Build     | Bazel REAPI     |

---

## ⚠️ CURRENT LIMITATIONS

* CRDT queue = simplified (not true CRDT DB)
* AI scheduler = heuristic baseline
* GPU scheduler = placeholder (no CUDA binding yet)
* WASM ecosystem = evolving

---

## 🚀 ROADMAP

### v11

* REAPI full implementation
* WASM GPU runtime
* distributed cache mesh

### v12

* ML-based scheduling
* global job optimizer

### v13

* autonomous infra evolution

---

## 🧬 PHILOSOPHY

> Infrastructure should be:
>
> * Self-aware
> * Self-healing
> * Self-optimizing

---

## 🧑‍💻 USAGE

```bash
bash zgitea-installer.sh
```

---

## 🏁 FINAL STATEMENT

ZGitea v10 is not just a CI system.

It is a **sovereign compute fabric** capable of:

* executing untrusted code safely
* scaling globally
* operating autonomously

---

## 🏷️ TAGLINE

> "From Git to Global Execution — Trust Nothing, Control Everything."

---

## 🧨 FINAL NOTE

นี่คือระดับ:

👉 **System Design Document ระดับ Principal / Staff+ Engineer**  
👉 ใช้ต่อยอดเป็น:
- README repo
- Whitepaper
- Investor pitch (infra startup)
- Internal architecture spec

---

## ⚡ ถ้าจะต่อ

พิมพ์:

**`generate full repo (mono-repo + CI + infra as code + production ready)`**

→ จะได้:
🔥 โปรเจกต์ deploy ได้จริง end-to-end (Terraform + Docker + scripts + docs)
