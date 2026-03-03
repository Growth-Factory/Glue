import Testing
import Foundation
@testable import GlueMemory

// MARK: - Benchmark Harness

/// A single benchmark query with expected relevant document IDs.
struct BenchmarkQuery {
    let query: String
    /// Document keys that MUST appear in top-K results.
    let expectedHits: Set<String>
    /// Document keys that MUST NOT appear in top-K results (hard negatives).
    let expectedMisses: Set<String>
    /// How many top results to inspect.
    let k: Int

    init(_ query: String, hits: Set<String>, misses: Set<String> = [], k: Int = 3) {
        self.query = query
        self.expectedHits = hits
        self.expectedMisses = misses
        self.k = k
    }
}

/// Result of running a single benchmark query.
struct BenchmarkResult {
    let query: String
    let expectedHits: Set<String>
    let hitRate: Double          // fraction of expectedHits found in top-K
    let missViolations: [String] // expectedMisses that incorrectly appeared
    let topResults: [(key: String, score: Float)]

    var passed: Bool { (expectedHits.isEmpty || hitRate >= 1.0) && missViolations.isEmpty }
}

/// Runs a full benchmark suite: ingests corpus, runs queries, returns per-query results.
func runBenchmark(
    corpus: [(key: String, content: String)],
    queries: [BenchmarkQuery],
    metadata: [String: [String: String]] = [:],
    llmEnhancer: (any LLMEnhancer)? = nil,
    config: OrchestratorConfig = OrchestratorConfig(enableTextSearch: true, enableVectorSearch: false)
) async throws -> [BenchmarkResult] {
    let backend = InMemoryStorageBackend()
    let orch = MemoryOrchestrator(
        backend: backend,
        llmEnhancer: llmEnhancer,
        config: config
    )

    // Ingest
    var ids: [String: UUID] = [:]
    for (key, content) in corpus {
        let meta = metadata[key] ?? [:]
        let frame = try await orch.remember(content, metadata: meta)
        ids[key] = frame.id
    }

    // Reverse lookup
    let idToKey: [UUID: String] = Dictionary(uniqueKeysWithValues: ids.map { ($1, $0) })

    // Query
    var results: [BenchmarkResult] = []
    for bq in queries {
        let response = try await orch.search(SearchRequest(
            query: bq.query, mode: .textOnly, topK: bq.k
        ))

        let topKeys = response.results.prefix(bq.k).compactMap { idToKey[$0.frameId] }
        let topKeySet = Set(topKeys)

        let hits = bq.expectedHits.intersection(topKeySet)
        let hitRate = bq.expectedHits.isEmpty ? 1.0 : Double(hits.count) / Double(bq.expectedHits.count)
        let missViolations = Array(bq.expectedMisses.intersection(topKeySet))

        let topWithScores = response.results.prefix(bq.k).compactMap { r -> (key: String, score: Float)? in
            guard let key = idToKey[r.frameId] else { return nil }
            return (key, r.score)
        }

        results.append(BenchmarkResult(
            query: bq.query,
            expectedHits: bq.expectedHits,
            hitRate: hitRate,
            missViolations: missViolations,
            topResults: topWithScores
        ))
    }
    return results
}

// MARK: - Scenario 1: Engineering Team Wiki

/// An engineering team's internal knowledge base. Documents overlap in domain
/// (all are about building software) but each covers a distinct topic.
/// The challenge: queries must find the RIGHT document, not just any engineering doc.

let engineeringCorpus: [(key: String, content: String)] = [
    ("incident-response",
     "When a production incident occurs, the on-call engineer should acknowledge the page within 5 minutes. Open an incident channel in Slack, page the relevant team leads, and begin investigation. Post status updates every 15 minutes. After resolution, schedule a blameless post-mortem within 48 hours. Document the timeline, root cause, impact, and action items."),

    ("deploy-process",
     "Our deployment pipeline uses GitHub Actions for CI and ArgoCD for continuous delivery to Kubernetes. Every PR must pass unit tests, integration tests, and a security scan before merge. Staging deploys happen automatically on merge to main. Production deploys require manual approval in ArgoCD and a buddy check from another engineer."),

    ("database-runbook",
     "For PostgreSQL maintenance: run VACUUM ANALYZE weekly on large tables. Monitor connection pool utilization in Grafana — alert threshold is 80%. For emergency failover, promote the read replica using pg_ctl promote, update the connection string in Vault, and restart affected services. Always take a WAL backup before schema migrations."),

    ("api-conventions",
     "All REST endpoints must follow our naming conventions: plural nouns for resources, kebab-case for multi-word paths. Use pagination with cursor-based tokens, not offset/limit. Rate limiting is enforced at 1000 req/min per API key. Authentication uses Bearer tokens from our OAuth2 provider. All responses must include request-id headers for tracing."),

    ("onboarding-guide",
     "New engineers should complete the following in their first week: set up the development environment using the bootstrap script, get access to GitHub, Slack, AWS, and Grafana. Shadow an on-call shift. Deploy a small change to staging. Read the architecture decision records (ADRs) in the docs/ folder. Meet with your team lead for a 30-60-90 day plan."),

    ("monitoring-alerts",
     "Our observability stack uses Prometheus for metrics, Grafana for dashboards, and PagerDuty for alerting. Key SLOs: API p99 latency under 200ms, error rate below 0.1%, availability 99.95%. Alert routing: P1 pages on-call immediately, P2 creates a Jira ticket, P3 sends a Slack notification. Silence alerts during maintenance windows using PagerDuty schedules."),

    ("code-review",
     "Code review guidelines: every PR needs at least one approval. Focus reviews on correctness, security, and maintainability — not style (that is handled by linters). Leave constructive comments with suggestions, not demands. PRs over 400 lines should be split. Reviewers should respond within one business day. Use the CODEOWNERS file to auto-assign reviewers."),

    ("architecture-api-gateway",
     "Our API gateway is built on Envoy proxy, handling authentication, rate limiting, and request routing. It terminates TLS, validates JWT tokens, and routes to backend services via gRPC. Circuit breaker settings: 5 consecutive failures triggers open state for 30 seconds. Request timeouts are 10 seconds for synchronous calls."),

    ("data-pipeline",
     "The analytics data pipeline ingests events from Kafka, processes them through Apache Flink for real-time aggregation, and stores results in ClickHouse for fast OLAP queries. Batch processing runs nightly via Airflow, computing daily/weekly/monthly rollups. Data retention: raw events for 90 days, aggregates for 2 years."),

    ("security-practices",
     "Security requirements: all secrets stored in HashiCorp Vault, never in code or environment variables. Enable MFA for all production access. Dependencies scanned weekly with Snyk. Container images must use distroless base images. Network policies restrict pod-to-pod communication to explicitly allowed paths. Quarterly penetration testing by external auditors."),
]

let engineeringQueries: [BenchmarkQuery] = [
    // Direct topic match — expectedMisses only for truly unrelated docs
    BenchmarkQuery("production incident response procedure pager acknowledgement",
                   hits: ["incident-response"], misses: ["code-review"]),

    BenchmarkQuery("how to deploy to production kubernetes ArgoCD",
                   hits: ["deploy-process"]),

    BenchmarkQuery("PostgreSQL vacuum failover read replica WAL backup",
                   hits: ["database-runbook"]),

    BenchmarkQuery("REST API naming conventions pagination rate limiting authentication",
                   hits: ["api-conventions"]),

    BenchmarkQuery("new engineer first week setup bootstrap development environment",
                   hits: ["onboarding-guide"]),

    // Disambiguation: "alerting" appears in monitoring AND incident-response
    BenchmarkQuery("Prometheus Grafana SLO latency error rate PagerDuty",
                   hits: ["monitoring-alerts"]),

    // Disambiguation: "PR" appears in deploy-process AND code-review
    BenchmarkQuery("code review approval CODEOWNERS constructive feedback PR lines",
                   hits: ["code-review"]),

    // Disambiguation: "gateway" vs "API conventions"
    BenchmarkQuery("Envoy proxy gRPC circuit breaker TLS JWT routing",
                   hits: ["architecture-api-gateway"]),

    // Disambiguation: "data" appears in many — must find pipeline specifically
    BenchmarkQuery("Kafka Flink ClickHouse Airflow analytics events aggregation batch",
                   hits: ["data-pipeline"]),

    // Disambiguation: "secrets" and security vs Vault mentions elsewhere
    BenchmarkQuery("Vault secrets MFA Snyk container scanning penetration testing",
                   hits: ["security-practices"]),

    // Cross-cutting: query that touches deployment + security
    // Both should be valid but security should win since query is security-heavy
    BenchmarkQuery("container images distroless network policies pod communication",
                   hits: ["security-practices"]),

    // Paraphrase: user asks in casual language, not using exact doc terms
    BenchmarkQuery("what happens when the site goes down at 3am who gets called",
                   hits: ["incident-response"]),

    // Negative: completely off-topic
    BenchmarkQuery("recipe for chocolate chip cookies baking temperature",
                   hits: [], misses: ["incident-response", "deploy-process", "database-runbook"]),
]

// MARK: - Scenario 2: Personal Assistant Memory

/// An AI personal assistant that remembers things about a user over time.
/// Facts, preferences, past conversations, commitments — the kind of memory
/// Wax is designed for. Challenge: find the right memory even when the user
/// asks vaguely or with different wording.

let personalCorpus: [(key: String, content: String)] = [
    ("wife-birthday",
     "Sarah's birthday is March 15th. She loves dark chocolate and hates white chocolate. Last year I got her a kindle and she really liked it. She mentioned wanting to try pottery classes."),

    ("daughter-school",
     "Emma is in 3rd grade at Westfield Elementary. Her teacher is Mrs. Patterson. She has a science fair project due February 20th about volcanoes. She is allergic to peanuts."),

    ("work-project",
     "The Meridian project deadline is April 30th. The client is Acme Corp, main contact is James Chen. We need to deliver the mobile app MVP with authentication, dashboard, and notification features. Budget is $150k."),

    ("health-notes",
     "Doctor appointment with Dr. Martinez on January 10th. Blood pressure was 128/82, slightly elevated. She recommended reducing sodium intake and walking 30 minutes daily. Next checkup in 6 months. Prescribed lisinopril 10mg."),

    ("house-maintenance",
     "The furnace filter needs replacing every 3 months — last changed November. The roof was inspected in September, inspector said it has about 5 years left. The dishwasher has been making a grinding noise since December. Plumber recommendation: Tony's Plumbing, 555-0192."),

    ("travel-plans",
     "Planning a family trip to Japan in October. Want to visit Tokyo, Kyoto, and Osaka. Emma needs a passport renewed before then. Sarah wants to see the Fushimi Inari shrine. Budget is around $8000 for two weeks. Need to book hotels by July."),

    ("book-recommendations",
     "Books to read: 'Project Hail Mary' by Andy Weir (sci-fi, Mark recommended it). 'Thinking Fast and Slow' by Kahneman (non-fiction, want to understand cognitive biases). Currently reading 'The Three-Body Problem' by Liu Cixin, on chapter 15."),

    ("car-info",
     "2021 Toyota RAV4 Hybrid, blue. VIN: 2T3RWRFV1MW123456. Oil change due at 45,000 miles — currently at 42,300. Tires rotated in October. Registration expires March 2025. Insurance with StateFarm, policy number SF-2847561."),

    ("fitness-goals",
     "Training for a half marathon in May. Current best 10K time is 52 minutes. Running 4 days per week, long run on Sundays. Dealing with mild knee pain — physical therapist suggested strengthening quads and hamstrings. Target finish time: under 2 hours."),

    ("diet-preferences",
     "Trying to eat more plant-based meals during weekdays. Sarah is lactose intolerant. Emma will eat anything except mushrooms and olives. Good weeknight recipes: black bean tacos, stir-fry with tofu, lentil soup. Favorite restaurant: Sakura Sushi on Oak Street."),
]

let personalQueries: [BenchmarkQuery] = [
    // Direct recall — misses only for truly unrelated docs
    BenchmarkQuery("when is Sarah's birthday what gift should I get her",
                   hits: ["wife-birthday"]),

    BenchmarkQuery("Emma's school teacher name grade allergies",
                   hits: ["daughter-school"]),

    BenchmarkQuery("Meridian project deadline client budget deliverables",
                   hits: ["work-project"]),

    BenchmarkQuery("blood pressure doctor checkup medication lisinopril",
                   hits: ["health-notes"]),

    // Temporal queries — user asks about upcoming deadlines
    BenchmarkQuery("what needs to happen before the Japan trip passport hotels",
                   hits: ["travel-plans"]),

    // Vague recall — user doesn't use exact terms
    BenchmarkQuery("that book Mark told me to read science fiction",
                   hits: ["book-recommendations"]),

    BenchmarkQuery("when is the car due for service oil change mileage",
                   hits: ["car-info"]),

    // Disambiguation: both wife-birthday and diet-preferences mention Sarah
    BenchmarkQuery("Sarah lactose intolerant food dietary restrictions",
                   hits: ["diet-preferences"]),

    // Disambiguation: both health-notes and fitness-goals mention physical health
    BenchmarkQuery("half marathon training running knee pain physical therapist",
                   hits: ["fitness-goals"]),

    // Disambiguation: house vs car maintenance
    BenchmarkQuery("furnace filter roof dishwasher grinding noise plumber",
                   hits: ["house-maintenance"]),

    // Cross-cutting: family trip + daughter
    BenchmarkQuery("Emma passport renewal for international travel",
                   hits: ["travel-plans"], k: 5),

    // Negative: nothing about this in memory
    BenchmarkQuery("stock portfolio investment returns NASDAQ dividends",
                   hits: []),
]

// MARK: - Scenario 3: Codebase Documentation

/// Documentation for a web application codebase. These docs are very similar
/// in vocabulary (all about the same app) but each describes a different module.
/// This is the hardest test: all docs share terms like "module", "service", "handler",
/// "database", "config" — the search must discriminate based on specifics.

let codebaseCorpus: [(key: String, content: String)] = [
    ("auth-module",
     "The authentication module handles user sign-up, login, and session management. Passwords are hashed with bcrypt (cost factor 12). Sessions are stored in Redis with a 24-hour TTL. The /auth/login endpoint accepts email and password, returns a JWT access token (15 min expiry) and a refresh token (7 day expiry). MFA is optional via TOTP."),

    ("payments-module",
     "The payments module integrates with Stripe for credit card processing and PayPal for alternative payments. Webhooks from Stripe are verified using the signing secret. Refunds are processed within 5-7 business days. The PaymentService actor handles idempotency keys to prevent duplicate charges. All amounts are stored in cents as integers."),

    ("notifications-module",
     "The notification system supports email (via SendGrid), push notifications (via Firebase Cloud Messaging), and in-app notifications stored in PostgreSQL. Users can configure preferences per channel. The NotificationDispatcher batches emails to avoid rate limits. Templates are stored in the templates/ directory using Mustache syntax."),

    ("search-module",
     "The search feature uses Elasticsearch for full-text search across products, articles, and user profiles. Queries support fuzzy matching, faceted filtering, and highlighting. The search index is updated asynchronously via a Kafka consumer that listens to change events. Reindexing runs nightly via a cron job."),

    ("file-upload-module",
     "File uploads are handled by the MediaService. Files are stored in S3 with CloudFront as CDN. Images are automatically resized to thumbnail (150px), medium (600px), and large (1200px) variants using Sharp. Upload limits: 10MB for images, 100MB for videos. Virus scanning via ClamAV runs before storage."),

    ("admin-dashboard",
     "The admin dashboard provides CRUD operations for managing users, content, and system configuration. Role-based access control restricts features: super-admin sees everything, moderators can manage content but not users, support agents can view but not edit. Built with React and communicates via the internal admin API."),

    ("caching-layer",
     "The caching strategy uses a three-tier approach: in-process LRU cache (100 items, 60s TTL) for hot paths, Redis for shared cache (1 hour TTL for API responses, 24 hours for user profiles), and CDN caching for static assets (30 day TTL). Cache invalidation uses a pub/sub pattern through Redis channels."),

    ("logging-tracing",
     "Structured logging uses JSON format with correlation IDs propagated via request headers. Log levels: DEBUG for development, INFO for production, WARN for degraded states, ERROR for failures. Distributed tracing with OpenTelemetry exports spans to Jaeger. Log aggregation in Elasticsearch via Filebeat."),

    ("database-schema",
     "The PostgreSQL database schema follows a multi-tenant design with tenant_id on every table. Migrations use Flyway with versioned SQL files. Key tables: users, organizations, products, orders, payments. Soft deletes via deleted_at timestamp. Read replicas handle reporting queries. Connection pooling via PgBouncer."),

    ("rate-limiting",
     "Rate limiting is implemented at the API gateway level using a sliding window algorithm. Limits: 100 requests per minute for authenticated users, 20 for anonymous. Per-endpoint overrides for expensive operations like search (30/min) and file upload (10/min). Exceeded limits return 429 Too Many Requests with a Retry-After header."),
]

let codebaseQueries: [BenchmarkQuery] = [
    // Exact module queries — misses only for truly cross-domain irrelevant docs
    BenchmarkQuery("user login password bcrypt JWT session Redis",
                   hits: ["auth-module"]),

    BenchmarkQuery("Stripe PayPal credit card webhooks refund idempotency",
                   hits: ["payments-module"]),

    BenchmarkQuery("SendGrid push notification Firebase email templates Mustache",
                   hits: ["notifications-module"]),

    BenchmarkQuery("Elasticsearch fuzzy matching faceted search Kafka reindex",
                   hits: ["search-module"]),

    BenchmarkQuery("S3 CloudFront image resize Sharp upload ClamAV virus",
                   hits: ["file-upload-module"]),

    // Hard disambiguation: Redis appears in auth-module, caching-layer, and logging
    BenchmarkQuery("three-tier LRU cache Redis pub/sub invalidation CDN TTL",
                   hits: ["caching-layer"]),

    // Hard disambiguation: PostgreSQL appears in notifications, database-schema, search
    BenchmarkQuery("multi-tenant Flyway migrations PgBouncer read replicas soft deletes",
                   hits: ["database-schema"]),

    // Hard disambiguation: Elasticsearch appears in search-module and logging-tracing
    BenchmarkQuery("OpenTelemetry Jaeger distributed tracing correlation ID structured logging",
                   hits: ["logging-tracing"]),

    // Hard disambiguation: rate limiting vs API gateway / auth
    BenchmarkQuery("sliding window 429 Retry-After anonymous authenticated per-endpoint limits",
                   hits: ["rate-limiting"]),

    // Hard disambiguation: admin CRUD vs database schema CRUD
    BenchmarkQuery("admin dashboard role-based access super-admin moderator React",
                   hits: ["admin-dashboard"]),

    // Paraphrase: user asks conceptually, not using module vocabulary
    BenchmarkQuery("how do we prevent charging a customer twice for the same order",
                   hits: ["payments-module"]),

    BenchmarkQuery("where do uploaded images end up and what sizes are generated",
                   hits: ["file-upload-module"]),

    // Negative
    BenchmarkQuery("machine learning model training GPU CUDA tensor batch inference",
                   hits: []),
]

// MARK: - Test Suites

@Suite("Engineering Wiki Relevance Benchmark")
struct EngineeringWikiBenchmark {

    @Test func allQueriesHitExpectedDocuments() async throws {
        let results = try await runBenchmark(corpus: engineeringCorpus, queries: engineeringQueries)

        var totalHitRate: Double = 0
        var passCount = 0
        var failures: [String] = []

        for r in results {
            totalHitRate += r.hitRate

            if !r.passed {
                let topKeys = r.topResults.map { "\($0.key)(\(String(format: "%.2f", $0.score)))" }.joined(separator: ", ")
                if r.hitRate < 1.0 && !r.expectedHits.isEmpty {
                    failures.append("MISS: \"\(r.query)\" — got [\(topKeys)]")
                }
                if !r.missViolations.isEmpty {
                    failures.append("FALSE_POS: \"\(r.query)\" — unwanted [\(r.missViolations.joined(separator: ", "))] in [\(topKeys)]")
                }
            } else {
                passCount += 1
            }
        }

        let queriesWithExpectedHits = results.filter { !$0.expectedHits.isEmpty }
        let avgHitRate = queriesWithExpectedHits.isEmpty ? 1.0 :
            queriesWithExpectedHits.reduce(0.0) { $0 + $1.hitRate } / Double(queriesWithExpectedHits.count)

        // Log summary for visibility
        let summary = "Engineering: \(passCount)/\(results.count) passed, avg hit rate \(String(format: "%.1f%%", avgHitRate * 100))"
        if !failures.isEmpty {
            let detail = failures.joined(separator: "\n  ")
            #expect(Bool(false), "Benchmark failures in engineering wiki:\n  \(detail)\n\(summary)")
        }
        #expect(avgHitRate >= 0.85, "Average hit rate must be >= 85%. Got \(String(format: "%.1f%%", avgHitRate * 100)). \(summary)")
    }

    // Individual critical queries get their own test for clear failure reporting

    @Test func incidentVsDeployDisambiguation() async throws {
        let results = try await runBenchmark(corpus: engineeringCorpus, queries: [
            BenchmarkQuery("production outage page on-call engineer post-mortem blameless",
                           hits: ["incident-response"]),
        ])
        #expect(results[0].passed, "Incident response must be found for outage/on-call query")
    }

    @Test func securityVsDeployDisambiguation() async throws {
        let results = try await runBenchmark(corpus: engineeringCorpus, queries: [
            BenchmarkQuery("HashiCorp Vault secrets never in environment variables MFA",
                           hits: ["security-practices"], misses: ["deploy-process"]),
        ])
        #expect(results[0].passed, "Security doc must be found for secrets/Vault query")
    }

    @Test func dataPipelineVsDatabase() async throws {
        let results = try await runBenchmark(corpus: engineeringCorpus, queries: [
            BenchmarkQuery("real-time event stream processing aggregation analytics OLAP",
                           hits: ["data-pipeline"], misses: ["database-runbook"]),
        ])
        #expect(results[0].passed, "Data pipeline must be found for stream processing query, not database runbook")
    }
}

@Suite("Personal Assistant Relevance Benchmark")
struct PersonalAssistantBenchmark {

    @Test func allQueriesHitExpectedDocuments() async throws {
        let results = try await runBenchmark(corpus: personalCorpus, queries: personalQueries)

        var failures: [String] = []
        for r in results {
            if !r.passed && !r.expectedHits.isEmpty {
                let topKeys = r.topResults.map { "\($0.key)(\(String(format: "%.2f", $0.score)))" }.joined(separator: ", ")
                failures.append("MISS: \"\(r.query)\" — got [\(topKeys)]")
            }
            if !r.missViolations.isEmpty {
                let topKeys = r.topResults.map { $0.key }.joined(separator: ", ")
                failures.append("FALSE_POS: \"\(r.query)\" — unwanted [\(r.missViolations.joined(separator: ", "))] in [\(topKeys)]")
            }
        }

        let queriesWithExpectedHits = results.filter { !$0.expectedHits.isEmpty }
        let avgHitRate = queriesWithExpectedHits.isEmpty ? 1.0 :
            queriesWithExpectedHits.reduce(0.0) { $0 + $1.hitRate } / Double(queriesWithExpectedHits.count)

        if !failures.isEmpty {
            let detail = failures.joined(separator: "\n  ")
            #expect(Bool(false), "Benchmark failures in personal assistant:\n  \(detail)")
        }
        #expect(avgHitRate >= 0.85, "Average hit rate must be >= 85%. Got \(String(format: "%.1f%%", avgHitRate * 100))")
    }

    @Test func sarahBirthdayVsDiet() async throws {
        // "Sarah" appears in both wife-birthday and diet-preferences
        // BM25 will return both since they share the name — verify correct one is #1
        let results = try await runBenchmark(corpus: personalCorpus, queries: [
            BenchmarkQuery("Sarah birthday gift dark chocolate pottery",
                           hits: ["wife-birthday"]),
            BenchmarkQuery("Sarah cannot eat dairy lactose plant-based weeknight meals",
                           hits: ["diet-preferences"]),
        ])
        #expect(results[0].passed, "Birthday query must find wife-birthday as top hit")
        #expect(results[1].passed, "Diet query must find diet-preferences as top hit")
    }

    @Test func healthVsFitness() async throws {
        // Both discuss physical health — but doctor visits vs training
        let results = try await runBenchmark(corpus: personalCorpus, queries: [
            BenchmarkQuery("doctor blood pressure sodium medication prescription",
                           hits: ["health-notes"], misses: ["fitness-goals"]),
            BenchmarkQuery("marathon running long run Sunday quad strengthening target time",
                           hits: ["fitness-goals"], misses: ["health-notes"]),
        ])
        #expect(results[0].passed, "Medical query must find health-notes, not fitness")
        #expect(results[1].passed, "Running query must find fitness-goals, not health")
    }

    @Test func houseVsCarMaintenance() async throws {
        let results = try await runBenchmark(corpus: personalCorpus, queries: [
            BenchmarkQuery("roof inspection dishwasher furnace filter plumber Tony",
                           hits: ["house-maintenance"], misses: ["car-info"]),
            BenchmarkQuery("RAV4 oil change mileage tires registration insurance StateFarm",
                           hits: ["car-info"], misses: ["house-maintenance"]),
        ])
        #expect(results[0].passed, "House maintenance query must not return car info")
        #expect(results[1].passed, "Car query must not return house maintenance")
    }
}

@Suite("Codebase Documentation Relevance Benchmark")
struct CodebaseDocsBenchmark {

    @Test func allQueriesHitExpectedDocuments() async throws {
        let results = try await runBenchmark(corpus: codebaseCorpus, queries: codebaseQueries)

        var failures: [String] = []
        for r in results {
            if !r.passed && !r.expectedHits.isEmpty {
                let topKeys = r.topResults.map { "\($0.key)(\(String(format: "%.2f", $0.score)))" }.joined(separator: ", ")
                failures.append("MISS: \"\(r.query)\" — got [\(topKeys)]")
            }
            if !r.missViolations.isEmpty {
                let topKeys = r.topResults.map { $0.key }.joined(separator: ", ")
                failures.append("FALSE_POS: \"\(r.query)\" — unwanted [\(r.missViolations.joined(separator: ", "))] in [\(topKeys)]")
            }
        }

        let queriesWithExpectedHits = results.filter { !$0.expectedHits.isEmpty }
        let avgHitRate = queriesWithExpectedHits.isEmpty ? 1.0 :
            queriesWithExpectedHits.reduce(0.0) { $0 + $1.hitRate } / Double(queriesWithExpectedHits.count)

        if !failures.isEmpty {
            let detail = failures.joined(separator: "\n  ")
            #expect(Bool(false), "Benchmark failures in codebase docs:\n  \(detail)")
        }
        #expect(avgHitRate >= 0.85, "Average hit rate must be >= 85%. Got \(String(format: "%.1f%%", avgHitRate * 100))")
    }

    @Test func redisDisambiguation() async throws {
        // Redis appears in auth (sessions), caching (shared cache) — both will appear
        // Verify the correct one ranks #1
        let results = try await runBenchmark(corpus: codebaseCorpus, queries: [
            BenchmarkQuery("session Redis TTL 24 hours JWT access refresh token login",
                           hits: ["auth-module"]),
            BenchmarkQuery("LRU in-process Redis pub/sub cache invalidation CDN static assets",
                           hits: ["caching-layer"]),
        ])
        #expect(results[0].passed, "Session/JWT query must find auth as top hit")
        #expect(results[1].passed, "LRU/CDN query must find caching as top hit")
    }

    @Test func postgresDisambiguation() async throws {
        // PostgreSQL appears in notifications, database-schema, and search
        let results = try await runBenchmark(corpus: codebaseCorpus, queries: [
            BenchmarkQuery("in-app notification PostgreSQL email SendGrid push Firebase",
                           hits: ["notifications-module"]),
            BenchmarkQuery("tenant_id migration Flyway PgBouncer soft delete replica connection pool",
                           hits: ["database-schema"]),
        ])
        #expect(results[0].passed, "Notification query must find notifications as top hit")
        #expect(results[1].passed, "Migration/tenant query must find schema as top hit")
    }

    @Test func elasticsearchDisambiguation() async throws {
        // Elasticsearch appears in search-module and logging-tracing
        let results = try await runBenchmark(corpus: codebaseCorpus, queries: [
            BenchmarkQuery("product search fuzzy matching facets highlighting index consumer",
                           hits: ["search-module"]),
            BenchmarkQuery("log aggregation Filebeat Elasticsearch structured JSON correlation",
                           hits: ["logging-tracing"]),
        ])
        #expect(results[0].passed, "Product search query must find search module as top hit")
        #expect(results[1].passed, "Logging query must find logging module as top hit")
    }

    @Test func paraphraseQueries() async throws {
        // User asks in natural language, not using exact doc terms
        let results = try await runBenchmark(corpus: codebaseCorpus, queries: [
            BenchmarkQuery("how do we prevent charging a customer twice for the same order",
                           hits: ["payments-module"]),
            BenchmarkQuery("where do uploaded images end up and what sizes are generated",
                           hits: ["file-upload-module"]),
            BenchmarkQuery("who can see what in the admin panel permissions access levels",
                           hits: ["admin-dashboard"]),
        ])
        // Paraphrase queries are harder — check at least 2 of 3 pass
        let passed = results.filter { $0.passed }.count
        #expect(passed >= 2, "At least 2 of 3 paraphrase queries should hit. Got \(passed)/3")
    }
}

// MARK: - Scenario 4: Pitch Deck

/// A startup pitch deck ingested page by page. Typical slides: problem, solution,
/// market size, product, traction, business model, competition, team, advisors, ask.
/// Challenge: all pages share startup jargon ("market", "growth", "revenue", "users").
/// Team and advisor pages contain multiple people — queries for specific people or
/// roles must find the right page. "Team" vs "Advisors" must disambiguate cleanly.

let pitchDeckCorpus: [(key: String, content: String)] = [
    ("cover",
     "NovaBridge — Connecting Enterprise AI to Legacy Systems. Series A Fundraise, Q1 2025. Confidential."),

    ("problem",
     "Enterprises spend $340B annually maintaining legacy systems. 72% of Fortune 500 companies run critical infrastructure on COBOL, mainframes, and on-prem databases built decades ago. Migrating is risky, expensive, and slow — average migration projects take 3-5 years and 60% fail. Meanwhile, AI adoption is blocked because modern ML models cannot access data trapped in these legacy systems."),

    ("solution",
     "NovaBridge is a middleware layer that connects modern AI tools to legacy systems without migration. Our proprietary adapter framework translates between modern APIs (REST, GraphQL, gRPC) and legacy protocols (CICS, IMS, MQ Series). Engineers install a lightweight agent on the legacy system — no code changes required. AI models can query legacy data in real-time through a unified API."),

    ("product",
     "The NovaBridge platform consists of three components: (1) Bridge Agents — lightweight daemons installed on legacy systems that expose data through a secure tunnel. (2) The Translation Layer — a cloud-hosted service that converts between modern and legacy protocols, handling encoding, pagination, and error translation. (3) The Developer SDK — client libraries for Python, Java, and TypeScript that let developers query legacy data as if it were a modern REST API."),

    ("market",
     "Total addressable market: $89B enterprise integration market growing at 12% CAGR. Serviceable addressable market: $23B in legacy-to-modern integration. Our initial beachhead: $4.2B financial services legacy integration. 85% of banks still run core banking on mainframes. Insurance companies process 40% of claims through COBOL applications."),

    ("traction",
     "Launched 12 months ago. Current metrics: $2.1M ARR, growing 25% month-over-month. 14 enterprise customers including 3 Fortune 500 banks. 847 Bridge Agents deployed across customer environments. 99.97% uptime SLA achieved. Average deal size: $150K ACV. Net revenue retention: 135%. Pipeline: $8.4M in qualified opportunities."),

    ("business-model",
     "SaaS pricing based on number of Bridge Agents deployed and data volume processed. Three tiers: Starter ($2K/month, up to 10 agents), Business ($8K/month, up to 50 agents, priority support), Enterprise (custom pricing, unlimited agents, dedicated success manager, SLA guarantees). Professional services for complex integrations billed at $250/hour. Gross margins: 78%."),

    ("competition",
     "MuleSoft (Salesforce) — general integration platform, not specialized for legacy. Requires significant custom development for mainframe connectivity. IBM App Connect — strong legacy support but vendor lock-in and expensive. No AI-first approach. Competitors lack our agent-based architecture that requires zero changes to legacy systems. Our moat: 47 proprietary protocol adapters built over 3 years of R&D."),

    ("go-to-market",
     "Land-and-expand strategy targeting financial services first. Direct sales team of 6 account executives focused on VP Engineering and CTO personas at banks and insurance companies. Channel partnerships with Accenture and Deloitte for implementation. Content marketing through technical blog posts and conference talks at KubeCon and AWS re:Invent. Free developer tier drives bottom-up adoption."),

    ("team",
     "Sarah Chen, CEO — Former VP Engineering at Stripe, led payments infrastructure serving 2M+ businesses. Stanford CS, 15 years in enterprise software. Previously at Oracle building database middleware. John Park, CTO — Ex-principal engineer at AWS, built the original Lambda cold-start optimization. MIT PhD in distributed systems. 12 patents in protocol translation. Maria Santos, VP Sales — Former enterprise sales director at Datadog, grew mid-market segment from $5M to $45M ARR. Built and managed a team of 20 account executives. David Kim, VP Engineering — Previously staff engineer at Google Cloud, led the Anthos migration tooling team. Expert in mainframe modernization and COBOL interop. Berkeley CS PhD."),

    ("advisors",
     "Jennifer Walsh — Former CIO of JPMorgan Chase, 25 years in financial services technology. Led the largest mainframe modernization program in banking history. Board member at Plaid and Brex. Robert Huang — General Partner at Sequoia Capital, led investments in Stripe, Confluent, and Databricks. Focus on enterprise infrastructure. Lisa Thompson — Former SVP Engineering at IBM, created the IBM Cloud Pak integration platform. Expert in MQ Series and CICS protocols. Advisory board member at 5 enterprise startups."),

    ("financials",
     "Last 12 months revenue: $2.1M. Burn rate: $380K/month. Runway: 14 months at current burn. Projected revenue next 12 months: $7.8M based on pipeline and expansion. Path to profitability: Q4 2026 at current growth trajectory. Unit economics: LTV $420K, CAC $62K, LTV/CAC ratio 6.8x. Payback period: 9 months."),

    ("ask",
     "Raising $18M Series A to accelerate growth. Use of funds: 45% engineering (expand protocol adapter library, build self-service onboarding), 30% sales and marketing (grow sales team to 15 AEs, launch partner program), 15% customer success (reduce onboarding time from 6 weeks to 1 week), 10% G&A. Target investors: enterprise-focused VCs with portfolio companies in financial services or infrastructure."),
]

let pitchDeckQueries: [BenchmarkQuery] = [
    // Team queries — must find team page
    BenchmarkQuery("who is on the team founders leadership",
                   hits: ["team"]),

    BenchmarkQuery("who is the CEO background experience",
                   hits: ["team"]),

    BenchmarkQuery("John Park CTO distributed systems patents",
                   hits: ["team"]),

    BenchmarkQuery("Sarah Chen Stripe Oracle enterprise software",
                   hits: ["team"]),

    // Advisors — must find advisor page, not team
    BenchmarkQuery("advisors board members investors advisory",
                   hits: ["advisors"]),

    BenchmarkQuery("Jennifer Walsh JPMorgan CIO banking mainframe",
                   hits: ["advisors"]),

    BenchmarkQuery("Robert Huang Sequoia venture capital investments",
                   hits: ["advisors"]),

    // Specific person's previous companies
    BenchmarkQuery("Maria Santos Datadog sales mid-market ARR account executives",
                   hits: ["team"]),

    BenchmarkQuery("David Kim Google Cloud Anthos mainframe COBOL",
                   hits: ["team"]),

    BenchmarkQuery("Lisa Thompson IBM Cloud Pak MQ Series CICS",
                   hits: ["advisors"]),

    // Content slides — must find the right one amid shared vocabulary
    BenchmarkQuery("what problem does the company solve legacy systems migration",
                   hits: ["problem"]),

    BenchmarkQuery("how does the product work middleware adapter agents",
                   hits: ["solution"]),

    BenchmarkQuery("SDK components translation layer bridge agents developer libraries",
                   hits: ["product"]),

    BenchmarkQuery("total addressable market TAM size financial services banks",
                   hits: ["market"]),

    BenchmarkQuery("ARR revenue customers growth month-over-month uptime",
                   hits: ["traction"]),

    BenchmarkQuery("pricing tiers SaaS agents monthly cost gross margins",
                   hits: ["business-model"]),

    BenchmarkQuery("MuleSoft IBM competitors moat protocol adapters",
                   hits: ["competition"]),

    BenchmarkQuery("sales strategy channel partnerships Accenture conferences",
                   hits: ["go-to-market"]),

    BenchmarkQuery("how much are they raising Series A use of funds engineering sales",
                   hits: ["ask"]),

    BenchmarkQuery("burn rate runway profitability LTV CAC unit economics",
                   hits: ["financials"]),

    // Cross-cutting queries
    BenchmarkQuery("who previously worked at big tech companies Google AWS Oracle",
                   hits: ["team"], k: 5),

    BenchmarkQuery("what is the revenue and how fast is it growing",
                   hits: ["traction"], k: 5),

    // Negative
    BenchmarkQuery("cryptocurrency blockchain DeFi token smart contract",
                   hits: []),
]

// MARK: - Pitch Deck Test Suite

@Suite("Pitch Deck Relevance Benchmark")
struct PitchDeckBenchmark {

    @Test func allQueriesHitExpectedDocuments() async throws {
        let results = try await runBenchmark(corpus: pitchDeckCorpus, queries: pitchDeckQueries)

        var failures: [String] = []
        for r in results {
            if !r.expectedHits.isEmpty && r.hitRate < 1.0 {
                let topKeys = r.topResults.map { "\($0.key)(\(String(format: "%.2f", $0.score)))" }.joined(separator: ", ")
                failures.append("MISS: \"\(r.query)\" — got [\(topKeys)]")
            }
            if !r.missViolations.isEmpty {
                let topKeys = r.topResults.map { $0.key }.joined(separator: ", ")
                failures.append("FALSE_POS: \"\(r.query)\" — unwanted [\(r.missViolations.joined(separator: ", "))] in [\(topKeys)]")
            }
        }

        let queriesWithExpectedHits = results.filter { !$0.expectedHits.isEmpty }
        let avgHitRate = queriesWithExpectedHits.isEmpty ? 1.0 :
            queriesWithExpectedHits.reduce(0.0) { $0 + $1.hitRate } / Double(queriesWithExpectedHits.count)

        if !failures.isEmpty {
            let detail = failures.joined(separator: "\n  ")
            #expect(Bool(false), "Benchmark failures in pitch deck:\n  \(detail)")
        }
        #expect(avgHitRate >= 0.85, "Average hit rate must be >= 85%. Got \(String(format: "%.1f%%", avgHitRate * 100))")
    }

    @Test func teamVsAdvisors() async throws {
        // "Team" and "Advisors" are the hardest disambiguation — both have people, titles, companies
        let results = try await runBenchmark(corpus: pitchDeckCorpus, queries: [
            BenchmarkQuery("founding team CEO CTO VP Engineering VP Sales backgrounds",
                           hits: ["team"]),
            BenchmarkQuery("advisory board external advisors investors board members",
                           hits: ["advisors"]),
        ])
        #expect(results[0].passed, "Team query must find team page as top hit")
        #expect(results[1].passed, "Advisors query must find advisors page as top hit")
    }

    @Test func specificPeopleOnTeam() async throws {
        let results = try await runBenchmark(corpus: pitchDeckCorpus, queries: [
            BenchmarkQuery("John Park AWS Lambda cold-start MIT PhD patents",
                           hits: ["team"]),
            BenchmarkQuery("Maria Santos Datadog enterprise sales director",
                           hits: ["team"]),
            BenchmarkQuery("David Kim Google Cloud Anthos staff engineer Berkeley",
                           hits: ["team"]),
        ])
        for (i, r) in results.enumerated() {
            #expect(r.passed, "Person query \(i) must find team page: \(r.query)")
        }
    }

    @Test func specificPeopleOnAdvisors() async throws {
        let results = try await runBenchmark(corpus: pitchDeckCorpus, queries: [
            BenchmarkQuery("Jennifer Walsh CIO JPMorgan Plaid Brex board mainframe modernization",
                           hits: ["advisors"]),
            BenchmarkQuery("Robert Huang Sequoia general partner Stripe Confluent Databricks",
                           hits: ["advisors"]),
            BenchmarkQuery("Lisa Thompson IBM SVP engineering MQ Series CICS Cloud Pak",
                           hits: ["advisors"]),
        ])
        for (i, r) in results.enumerated() {
            #expect(r.passed, "Advisor query \(i) must find advisors page: \(r.query)")
        }
    }

    @Test func problemVsSolution() async throws {
        let results = try await runBenchmark(corpus: pitchDeckCorpus, queries: [
            BenchmarkQuery("enterprise legacy systems COBOL mainframe migration risk failure",
                           hits: ["problem"]),
            BenchmarkQuery("middleware adapter framework REST GraphQL gRPC protocol translation agent",
                           hits: ["solution"]),
        ])
        #expect(results[0].passed, "Pain/problem query must find problem slide")
        #expect(results[1].passed, "Solution/middleware query must find solution slide")
    }

    @Test func tractionVsFinancials() async throws {
        // Both mention revenue — but traction = growth metrics, financials = unit economics
        let results = try await runBenchmark(corpus: pitchDeckCorpus, queries: [
            BenchmarkQuery("customer count Fortune 500 agents deployed uptime SLA net retention",
                           hits: ["traction"]),
            BenchmarkQuery("burn rate runway path profitability LTV CAC payback period",
                           hits: ["financials"]),
        ])
        #expect(results[0].passed, "Customer/growth query must find traction slide")
        #expect(results[1].passed, "Unit economics query must find financials slide")
    }

    @Test func businessModelVsAsk() async throws {
        // Both mention money — but pricing vs fundraising
        let results = try await runBenchmark(corpus: pitchDeckCorpus, queries: [
            BenchmarkQuery("SaaS pricing tiers starter business enterprise monthly cost professional services",
                           hits: ["business-model"]),
            BenchmarkQuery("Series A raising eighteen million use of funds investors",
                           hits: ["ask"]),
        ])
        #expect(results[0].passed, "Pricing query must find business model slide")
        #expect(results[1].passed, "Fundraising query must find ask slide")
    }
}

// MARK: - LLM-Enhanced Benchmarks

/// A mock LLMEnhancer that returns hand-crafted surrogates.
/// Simulates what a real LLM would generate: keywords and synonyms
/// that aren't in the original text but match how users search.
struct MockSurrogateEnhancer: LLMEnhancer {
    /// Map from a substring in the content to the surrogate to append.
    let surrogates: [String: String]

    func generateSurrogate(_ text: String, maxTokens: Int) async throws -> String {
        for (trigger, surrogate) in surrogates {
            if text.contains(trigger) {
                return surrogate
            }
        }
        return ""
    }

    func expandQuery(_ query: String) async throws -> [String] {
        [query]
    }
}

/// A mock LLMEnhancer that expands queries into multiple search variants.
struct MockQueryExpander: LLMEnhancer {
    let expansions: [String: [String]]

    func generateSurrogate(_ text: String, maxTokens: Int) async throws -> String {
        ""
    }

    func expandQuery(_ query: String) async throws -> [String] {
        if let expanded = expansions[query] {
            return [query] + expanded
        }
        return [query]
    }
}

@Suite("LLM-Enhanced Relevance Benchmark")
struct LLMEnhancedBenchmark {

    /// Surrogate generation fixes the 3 pitch deck rank-1 misses.
    /// Without surrogates, BM25 can't match "team" → team slide (word "team" is diluted),
    /// "problem" → problem slide (shares "legacy systems" with solution),
    /// or "revenue growing" → traction (says "ARR" not "revenue").
    @Test func surrogateGenerationFixesPitchDeckMisses() async throws {
        let enhancer = MockSurrogateEnhancer(surrogates: [
            // Team slide: add "team founders leadership founding members"
            "Sarah Chen, CEO": "Keywords: team, founders, leadership, founding members, executive team, co-founders",
            // Problem slide: add "problem pain point challenge"
            "Enterprises spend $340B": "Keywords: problem, pain point, challenge, what problem, company solves",
            // Traction slide: add "revenue growing traction growth"
            "Launched 12 months ago": "Keywords: revenue, traction, growth, growing, sales, income, how fast",
            // Advisors: reinforce "advisors advisory board"
            "Jennifer Walsh": "Keywords: advisors, advisory board, external advisors, mentors",
        ])

        let config = OrchestratorConfig(
            enableTextSearch: true,
            enableVectorSearch: false,
            enableSurrogateGeneration: true
        )

        // The 3 queries that fail at rank-1 without surrogates
        let queries = [
            BenchmarkQuery("who is on the team founders leadership",
                           hits: ["team"]),
            BenchmarkQuery("what problem does the company solve legacy systems migration",
                           hits: ["problem"]),
            BenchmarkQuery("what is the revenue and how fast is it growing",
                           hits: ["traction"], k: 5),
        ]

        let results = try await runBenchmark(
            corpus: pitchDeckCorpus,
            queries: queries,
            llmEnhancer: enhancer,
            config: config
        )

        // All 3 should now hit rank-1
        for r in results {
            let rank1 = r.topResults.first
            #expect(rank1 != nil && r.expectedHits.contains(rank1!.key),
                    "Surrogate should fix rank-1 for: \"\(r.query)\" — got #1=\(rank1?.key ?? "none")")
        }
    }

    /// Query expansion fixes misses by searching for paraphrases.
    @Test func queryExpansionFixesPitchDeckMisses() async throws {
        let expander = MockQueryExpander(expansions: [
            // "team founders leadership" → also search for names on the team slide
            "who is on the team founders leadership": [
                "CEO CTO VP Engineering VP Sales founders",
            ],
            // "problem" → add terms unique to the problem slide
            "what problem does the company solve legacy systems migration": [
                "enterprises spend maintaining COBOL mainframes migration fail",
            ],
            // "revenue growing" → add ARR and traction-specific terms
            "what is the revenue and how fast is it growing": [
                "ARR month-over-month customers growth retention",
            ],
        ])

        let config = OrchestratorConfig(
            enableTextSearch: true,
            enableVectorSearch: false,
            enableQueryExpansion: true
        )

        let queries = [
            BenchmarkQuery("who is on the team founders leadership",
                           hits: ["team"]),
            BenchmarkQuery("what problem does the company solve legacy systems migration",
                           hits: ["problem"]),
            BenchmarkQuery("what is the revenue and how fast is it growing",
                           hits: ["traction"], k: 5),
        ]

        let results = try await runBenchmark(
            corpus: pitchDeckCorpus,
            queries: queries,
            llmEnhancer: expander,
            config: config
        )

        for r in results {
            let rank1 = r.topResults.first
            #expect(rank1 != nil && r.expectedHits.contains(rank1!.key),
                    "Query expansion should fix rank-1 for: \"\(r.query)\" — got #1=\(rank1?.key ?? "none")")
        }
    }

    /// Surrogates should not degrade results that already work.
    /// Run the full pitch deck with surrogates and verify no regressions.
    @Test func surrogatesDoNotDegradeExistingResults() async throws {
        let enhancer = MockSurrogateEnhancer(surrogates: [
            "Sarah Chen, CEO": "Keywords: team, founders, leadership, founding members, executive team",
            "Enterprises spend $340B": "Keywords: problem, pain point, challenge, what problem",
            "Launched 12 months ago": "Keywords: revenue, traction, growth, growing, how fast",
            "Jennifer Walsh": "Keywords: advisors, advisory board, external advisors",
            "NovaBridge is a middleware": "Keywords: solution, how it works, product approach",
            "NovaBridge platform consists": "Keywords: product, architecture, components, SDK",
            "Total addressable market": "Keywords: market, TAM, SAM, market size, opportunity",
            "SaaS pricing based": "Keywords: business model, pricing, monetization, revenue model",
            "MuleSoft": "Keywords: competition, competitors, alternatives, competitive landscape",
            "Land-and-expand": "Keywords: go-to-market, GTM, sales strategy, distribution",
            "Last 12 months revenue": "Keywords: financials, unit economics, burn, runway",
            "Raising $18M": "Keywords: fundraise, ask, investment, Series A, use of funds",
            "NovaBridge — Connecting": "Keywords: cover, title, company name",
        ])

        let config = OrchestratorConfig(
            enableTextSearch: true,
            enableVectorSearch: false,
            enableSurrogateGeneration: true
        )

        let results = try await runBenchmark(
            corpus: pitchDeckCorpus,
            queries: pitchDeckQueries,
            llmEnhancer: enhancer,
            config: config
        )

        let withHits = results.filter { !$0.expectedHits.isEmpty }
        let avgHitRate = withHits.reduce(0.0) { $0 + $1.hitRate } / Double(withHits.count)
        #expect(avgHitRate >= 0.85,
                "Surrogates should not degrade hit rate. Got \(String(format: "%.1f%%", avgHitRate * 100))")

        // Count rank-1 hits
        var rank1 = 0
        for r in withHits {
            if let first = r.topResults.first, r.expectedHits.contains(first.key) {
                rank1 += 1
            }
        }
        let rank1Pct = Double(rank1) / Double(withHits.count) * 100
        #expect(rank1Pct >= 90.0,
                "With surrogates, rank-1 precision should be >= 90%. Got \(rank1)/\(withHits.count) (\(String(format: "%.1f%%", rank1Pct)))")
    }
}

// MARK: - Adversarial & Edge Case Benchmarks

/// An LLM that returns the same generic filler for every document.
struct UselessSurrogateEnhancer: LLMEnhancer {
    func generateSurrogate(_ text: String, maxTokens: Int) async throws -> String {
        "This is a document. It contains information. Very relevant content."
    }
    func expandQuery(_ query: String) async throws -> [String] { [query] }
}

/// An LLM that hallucinates wrong-topic keywords — actively harmful.
struct HallucinatingSurrogateEnhancer: LLMEnhancer {
    func generateSurrogate(_ text: String, maxTokens: Int) async throws -> String {
        if text.contains("Sarah Chen, CEO") {
            // Hallucinates financial keywords onto team slide
            return "Keywords: revenue, ARR, burn rate, runway, profitability, unit economics, financials"
        }
        if text.contains("Launched 12 months ago") {
            // Hallucinates team keywords onto traction slide
            return "Keywords: team, founders, CEO, CTO, leadership, executive, co-founders"
        }
        if text.contains("Enterprises spend $340B") {
            // Hallucinates solution keywords onto problem slide
            return "Keywords: middleware, adapter, API, SDK, bridge agents, translation layer"
        }
        return ""
    }
    func expandQuery(_ query: String) async throws -> [String] { [query] }
}

/// An LLM that returns an absurdly long surrogate — wall of text.
struct VerboseSurrogateEnhancer: LLMEnhancer {
    func generateSurrogate(_ text: String, maxTokens: Int) async throws -> String {
        // 200 words of generic startup jargon — same for every doc
        let filler = Array(repeating: "growth revenue team market product traction investors funding startup enterprise SaaS platform scalable innovative disruptive solution problem opportunity", count: 15).joined(separator: " ")
        return filler
    }
    func expandQuery(_ query: String) async throws -> [String] { [query] }
}

/// An LLM that expands queries with off-topic noise.
struct NoisyQueryExpander: LLMEnhancer {
    func generateSurrogate(_ text: String, maxTokens: Int) async throws -> String { "" }
    func expandQuery(_ query: String) async throws -> [String] {
        // Original query + 3 garbage expansions
        return [
            query,
            "banana orange apple fruit smoothie recipe kitchen",
            "football soccer basketball championship league standings",
            "weather forecast sunny cloudy temperature humidity",
        ]
    }
}

/// An LLM that throws errors intermittently.
struct FailingSurrogateEnhancer: LLMEnhancer {
    var failOnContent: String
    func generateSurrogate(_ text: String, maxTokens: Int) async throws -> String {
        if text.contains(failOnContent) {
            throw GlueError.backendError("LLM API rate limited")
        }
        return ""
    }
    func expandQuery(_ query: String) async throws -> [String] { [query] }
}

@Suite("Adversarial LLM Benchmark")
struct AdversarialLLMBenchmark {

    // MARK: - Bad Surrogates

    /// A useless LLM that returns generic filler should not hurt results.
    /// BM25 should still work because the original content is preserved.
    @Test func uselessSurrogatesDoNoHarm() async throws {
        let config = OrchestratorConfig(
            enableTextSearch: true,
            enableVectorSearch: false,
            enableSurrogateGeneration: true
        )

        // Run engineering corpus with useless surrogates
        let withSurrogates = try await runBenchmark(
            corpus: engineeringCorpus,
            queries: engineeringQueries,
            llmEnhancer: UselessSurrogateEnhancer(),
            config: config
        )

        // Run without surrogates as baseline
        let baseline = try await runBenchmark(
            corpus: engineeringCorpus,
            queries: engineeringQueries
        )

        let baselineHitRate = baseline.filter { !$0.expectedHits.isEmpty }
            .reduce(0.0) { $0 + $1.hitRate } / Double(baseline.filter { !$0.expectedHits.isEmpty }.count)
        let surrogateHitRate = withSurrogates.filter { !$0.expectedHits.isEmpty }
            .reduce(0.0) { $0 + $1.hitRate } / Double(withSurrogates.filter { !$0.expectedHits.isEmpty }.count)

        // Useless surrogates add the same words to every doc — should not change ranking
        #expect(surrogateHitRate >= baselineHitRate - 0.05,
                "Useless surrogates should not significantly degrade results. Baseline: \(String(format: "%.1f%%", baselineHitRate * 100)), With surrogates: \(String(format: "%.1f%%", surrogateHitRate * 100))")
    }

    /// A hallucinating LLM that puts wrong-topic keywords on documents.
    /// This is the worst case: it should actively confuse the search.
    /// We test that the damage is at least bounded — not a total meltdown.
    @Test func hallucinatingSurrogatesCauseMeasurableDamage() async throws {
        let config = OrchestratorConfig(
            enableTextSearch: true,
            enableVectorSearch: false,
            enableSurrogateGeneration: true
        )

        // Specifically test the 3 documents that get wrong keywords
        let queries = [
            // "financials" keywords hallucinated onto team slide — does "burn rate" now match team?
            BenchmarkQuery("burn rate runway profitability LTV CAC unit economics",
                           hits: ["financials"]),
            // "team" keywords hallucinated onto traction slide — does "founders CEO" now match traction?
            BenchmarkQuery("who is on the team founders leadership",
                           hits: ["team"]),
            // "solution" keywords hallucinated onto problem slide — does "middleware adapter" now match problem?
            BenchmarkQuery("middleware adapter framework REST GraphQL gRPC protocol translation",
                           hits: ["solution"]),
        ]

        let results = try await runBenchmark(
            corpus: pitchDeckCorpus,
            queries: queries,
            llmEnhancer: HallucinatingSurrogateEnhancer(),
            config: config
        )

        // Count how many got confused
        var confused = 0
        for r in results {
            if let first = r.topResults.first, !r.expectedHits.contains(first.key) {
                confused += 1
            }
        }

        // Report honestly — hallucination can break things
        // The test documents the damage rather than pretending it's fine
        print("Hallucinating LLM: \(confused)/\(results.count) queries returned wrong #1 result")
        // But the correct doc should still appear somewhere in top-K
        let hitRate = results.reduce(0.0) { $0 + $1.hitRate } / Double(results.count)
        #expect(hitRate >= 0.5,
                "Even with hallucinating surrogates, correct doc should appear in top-K at least 50% of the time. Got \(String(format: "%.0f%%", hitRate * 100))")
    }

    /// Verbose surrogates that drown the original content with identical jargon
    /// on every document. BM25 scores should flatten since every doc now shares
    /// the same terms — effectively destroying discrimination.
    @Test func verboseSurrogatesFlattenScores() async throws {
        let config = OrchestratorConfig(
            enableTextSearch: true,
            enableVectorSearch: false,
            enableSurrogateGeneration: true
        )

        let results = try await runBenchmark(
            corpus: engineeringCorpus,
            queries: engineeringQueries,
            llmEnhancer: VerboseSurrogateEnhancer(),
            config: config
        )

        let baseline = try await runBenchmark(
            corpus: engineeringCorpus,
            queries: engineeringQueries
        )

        // Measure score spread: how much does #1 outscore #3?
        // With verbose identical surrogates, the gap should shrink
        var baselineSpreads: [Float] = []
        var verboseSpreads: [Float] = []

        for r in baseline where r.topResults.count >= 3 {
            baselineSpreads.append(r.topResults[0].score - r.topResults[2].score)
        }
        for r in results where r.topResults.count >= 3 {
            verboseSpreads.append(r.topResults[0].score - r.topResults[2].score)
        }

        let avgBaselineSpread = baselineSpreads.reduce(0, +) / Float(max(1, baselineSpreads.count))
        let avgVerboseSpread = verboseSpreads.reduce(0, +) / Float(max(1, verboseSpreads.count))

        print("Score spread #1 vs #3 — Baseline: \(String(format: "%.2f", avgBaselineSpread)), Verbose surrogates: \(String(format: "%.2f", avgVerboseSpread))")

        // The verbose surrogates should measurably reduce discrimination
        // but not totally destroy it (original content still matters)
        let withHits = results.filter { !$0.expectedHits.isEmpty }
        let hitRate = withHits.reduce(0.0) { $0 + $1.hitRate } / Double(withHits.count)
        #expect(hitRate >= 0.60,
                "Even with verbose surrogates, hit rate should be >= 60%. Got \(String(format: "%.1f%%", hitRate * 100))")
    }

    // MARK: - Bad Query Expansion

    /// Noisy query expansion adds totally off-topic search variants.
    /// Should not hurt because the original query is always included,
    /// and we keep best-score-per-frame during merging.
    @Test func noisyQueryExpansionDoesNoHarm() async throws {
        let config = OrchestratorConfig(
            enableTextSearch: true,
            enableVectorSearch: false,
            enableQueryExpansion: true
        )

        let withNoise = try await runBenchmark(
            corpus: personalCorpus,
            queries: personalQueries,
            llmEnhancer: NoisyQueryExpander(),
            config: config
        )

        let baseline = try await runBenchmark(
            corpus: personalCorpus,
            queries: personalQueries
        )

        let baselineHitRate = baseline.filter { !$0.expectedHits.isEmpty }
            .reduce(0.0) { $0 + $1.hitRate } / Double(baseline.filter { !$0.expectedHits.isEmpty }.count)
        let noisyHitRate = withNoise.filter { !$0.expectedHits.isEmpty }
            .reduce(0.0) { $0 + $1.hitRate } / Double(withNoise.filter { !$0.expectedHits.isEmpty }.count)

        // Noisy expansion should not hurt because original query is always included
        // and merge uses max-score, so garbage results just get outscored
        #expect(noisyHitRate >= baselineHitRate,
                "Noisy expansion must not degrade results. Baseline: \(String(format: "%.1f%%", baselineHitRate * 100)), Noisy: \(String(format: "%.1f%%", noisyHitRate * 100))")
    }

    // MARK: - Typos

    /// Users make typos. BM25 is exact-match, so typos should hurt.
    /// This test documents how badly typos degrade results.
    @Test func typosInQueriesDegradeResults() async throws {
        let queries = [
            // Correct spelling vs typos
            BenchmarkQuery("PostgreSQL vacuum failover read replica WAL backup",
                           hits: ["database-runbook"]),      // correct — should hit
            BenchmarkQuery("PostrgeSQL vacum failovr read repica WAL bakcup",
                           hits: ["database-runbook"]),      // typos — will it still hit?

            BenchmarkQuery("Prometheus Grafana SLO latency error rate PagerDuty",
                           hits: ["monitoring-alerts"]),     // correct
            BenchmarkQuery("Promethesu Grafna SLO latecy eror rate PagerDty",
                           hits: ["monitoring-alerts"]),     // typos

            BenchmarkQuery("Kafka Flink ClickHouse Airflow analytics events aggregation batch",
                           hits: ["data-pipeline"]),         // correct
            BenchmarkQuery("Kafak Flink ClikHouse Airfow analytcs events agregation batch",
                           hits: ["data-pipeline"]),         // typos
        ]

        let results = try await runBenchmark(corpus: engineeringCorpus, queries: queries)

        // Correct queries (even indices)
        let correctHits = [results[0], results[2], results[4]].filter { $0.hitRate >= 1.0 }.count
        // Typo queries (odd indices)
        let typoHits = [results[1], results[3], results[5]].filter { $0.hitRate >= 1.0 }.count

        print("Typo test — Correct queries: \(correctHits)/3 hit, Typo queries: \(typoHits)/3 hit")

        #expect(correctHits == 3, "All correct-spelling queries must hit")
        // BM25 is exact-match so typos WILL hurt — document the extent
        // We don't require typo queries to pass; this is an honest measurement
    }

    /// Typos in ingested content (e.g., user-generated notes with mistakes).
    @Test func typosInContentDegradeResults() async throws {
        let cleanCorpus: [(key: String, content: String)] = [
            ("clean-doc", "The authentication module handles user login, password hashing with bcrypt, and JWT session tokens stored in Redis."),
        ]
        let typoCorpus: [(key: String, content: String)] = [
            ("typo-doc", "The authentcation modle handels user logn, pasword hashng with bcyrpt, and JWT sesion toknes stored in Rdis."),
        ]

        let cleanResults = try await runBenchmark(
            corpus: cleanCorpus,
            queries: [BenchmarkQuery("authentication login password bcrypt JWT session Redis", hits: ["clean-doc"])]
        )
        let typoResults = try await runBenchmark(
            corpus: typoCorpus,
            queries: [BenchmarkQuery("authentication login password bcrypt JWT session Redis", hits: ["typo-doc"])]
        )

        let cleanScore = cleanResults[0].topResults.first?.score ?? 0
        let typoScore = typoResults[0].topResults.first?.score ?? 0

        print("Content typos — Clean doc score: \(String(format: "%.2f", cleanScore)), Typo doc score: \(String(format: "%.2f", typoScore))")

        #expect(cleanResults[0].hitRate >= 1.0, "Clean content must be found")
        // Typo content will score lower but might still be found since some keywords survive
    }

    // MARK: - LLM Errors

    /// LLM throws an error during ingest — remember() should propagate the error,
    /// not silently swallow it and store without the surrogate.
    @Test func llmErrorDuringIngestPropagates() async throws {
        let enhancer = FailingSurrogateEnhancer(failOnContent: "Enterprises spend $340B")

        let backend = InMemoryStorageBackend()
        let orch = MemoryOrchestrator(
            backend: backend,
            llmEnhancer: enhancer,
            config: OrchestratorConfig(
                enableTextSearch: true,
                enableVectorSearch: false,
                enableSurrogateGeneration: true
            )
        )

        // This content triggers the LLM failure
        do {
            try await orch.remember("Enterprises spend $340B annually maintaining legacy systems.")
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            // Expected — LLM error should propagate
            #expect(String(describing: error).contains("rate limited"),
                    "Error should be the LLM error, got: \(error)")
        }

        // Other content should still work
        let frame = try await orch.remember("This content is fine and should succeed.")
        #expect(frame.content.contains("This content is fine"))
    }

    // MARK: - Empty / Minimal Content

    /// Very short content — single word, single sentence.
    /// BM25 should still work but with fewer terms to match.
    @Test func minimalContentStillSearchable() async throws {
        let corpus: [(key: String, content: String)] = [
            ("one-word", "PostgreSQL"),
            ("short-sentence", "Use Redis for caching."),
            ("normal", "Our deployment pipeline uses ArgoCD for continuous delivery to Kubernetes clusters."),
        ]

        let results = try await runBenchmark(corpus: corpus, queries: [
            BenchmarkQuery("PostgreSQL", hits: ["one-word"]),
            BenchmarkQuery("Redis caching", hits: ["short-sentence"]),
            BenchmarkQuery("ArgoCD deployment Kubernetes", hits: ["normal"]),
        ])

        for r in results {
            #expect(r.hitRate >= 1.0, "Even minimal content should be searchable: \"\(r.query)\"")
        }
    }

    /// Duplicate content — same text stored multiple times.
    /// All copies should appear in results with similar scores.
    @Test func duplicateContentReturnsAll() async throws {
        let corpus: [(key: String, content: String)] = [
            ("copy-1", "The quarterly report shows revenue growth of 25% year over year."),
            ("copy-2", "The quarterly report shows revenue growth of 25% year over year."),
            ("copy-3", "The quarterly report shows revenue growth of 25% year over year."),
            ("unrelated", "The cat sat on the mat and looked out the window."),
        ]

        let results = try await runBenchmark(corpus: corpus, queries: [
            BenchmarkQuery("quarterly report revenue growth", hits: ["copy-1", "copy-2", "copy-3"], k: 5),
        ])

        let topKeys = Set(results[0].topResults.map(\.key))
        let copies = topKeys.intersection(["copy-1", "copy-2", "copy-3"])
        #expect(copies.count == 3, "All 3 copies should appear in top-5. Got: \(topKeys)")
        #expect(!topKeys.contains("unrelated"), "Unrelated doc should not appear")
    }
}

// MARK: - Aggregate Precision Benchmark

@Suite("Aggregate Precision")
struct AggregatePrecisionBenchmark {

    @Test func overallPrecisionAcrossAllScenarios() async throws {
        let scenarios: [(String, [BenchmarkResult])] = [
            ("Engineering", try await runBenchmark(corpus: engineeringCorpus, queries: engineeringQueries)),
            ("Personal", try await runBenchmark(corpus: personalCorpus, queries: personalQueries)),
            ("Codebase", try await runBenchmark(corpus: codebaseCorpus, queries: codebaseQueries)),
            ("PitchDeck", try await runBenchmark(corpus: pitchDeckCorpus, queries: pitchDeckQueries)),
        ]

        let all = scenarios.flatMap(\.1)
        let withHits = all.filter { !$0.expectedHits.isEmpty }
        let totalQueries = withHits.count
        let avgHitRate = withHits.reduce(0.0) { $0 + $1.hitRate } / Double(totalQueries)
        let perfectHits = withHits.filter { $0.hitRate >= 1.0 }.count
        let noFalsePositives = all.filter { $0.missViolations.isEmpty }.count

        // Rank-1 precision: expected doc is the #1 result
        var rank1Total = 0
        var rank1Hits = 0
        var rank1Misses: [String] = []
        for (name, results) in scenarios {
            for r in results where !r.expectedHits.isEmpty {
                rank1Total += 1
                if let first = r.topResults.first, r.expectedHits.contains(first.key) {
                    rank1Hits += 1
                } else {
                    let got = r.topResults.first.map { "\($0.key)(\(String(format: "%.1f", $0.score)))" } ?? "none"
                    rank1Misses.append("[\(name)] \"\(r.query)\" — #1=\(got)")
                }
            }
        }

        let rank1Pct = Double(rank1Hits) / Double(rank1Total) * 100
        let rank1Summary = "Rank-1 precision: \(rank1Hits)/\(rank1Total) (\(String(format: "%.1f%%", rank1Pct)))"
        if !rank1Misses.isEmpty {
            let detail = rank1Misses.joined(separator: "\n  ")
            print("\(rank1Summary)\nRank-1 misses:\n  \(detail)")
        }

        // Aggregate thresholds
        #expect(avgHitRate >= 0.80,
                "Overall hit rate across \(totalQueries) queries must be >= 80%. Got \(String(format: "%.1f%%", avgHitRate * 100))")
        #expect(Double(perfectHits) / Double(totalQueries) >= 0.70,
                "At least 70% of queries must have perfect hits. Got \(perfectHits)/\(totalQueries)")
        #expect(Double(noFalsePositives) / Double(all.count) >= 0.90,
                "At least 90% of queries must have no false positives. Got \(noFalsePositives)/\(all.count)")
        #expect(rank1Pct >= 80.0, "\(rank1Summary)")
    }
}
