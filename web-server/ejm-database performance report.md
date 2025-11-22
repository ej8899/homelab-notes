# Ddatabse Concurrency and Throughput Performance Report

## Executive Summary

The primary goal of this testing was to determine the most stable and performant database solution (MySQL vs. SQLite) for handling high-concurrency write requests on the current shared hosting environment.

**Conclusion:** **MySQL is the clear, superior choice for this environment.**

1.  **Host Limitation:** The server's primary bottleneck is the **Web Host's PHP Process Limit**, which is reached between 100 and 500 simultaneous requests.
2.  **Database Performance:** Within the host's stable limits ($\le 100$ concurrency), MySQL is $\mathbf{100\%}$ reliable and delivers $\mathbf{30\%}$ higher sustained throughput than SQLite.
3.  **SQLite Failure Mode:** SQLite failed during both burst and sustained high-concurrency tests due to **file-locking contention**, leading to unacceptable latency and dropped transactions.

---

## 1. Environment Constraints and Primary Bottleneck

Initial testing at 500 simultaneous requests revealed a critical host-level limitation, unrelated to the database:

| Metric | Result (c=500 MySQL Test) | Interpretation |
| :--- | :--- | :--- |
| **Successful Writes** | 72 | Approximate hard concurrency limit for PHP scripts. |
| **Failed/Errored** | 428 | Requests were rejected by the host's web server. |
| **Failure Samples** | HTTP 301, HTTP 0 | Indicates the server ran out of available PHP worker processes (PHP-FPM) and killed the request immediately. |

**Key Finding: PHP Process Limit**
The web host imposes a strict limit on the number of concurrent PHP processes that can execute at any given moment. When this limit is exceeded, the server returns immediate non-database errors, preventing the application from scaling traffic past the $\mathbf{100-500}$ range. This limit is the maximum ceiling for **any** application on this server. 

---

## 2. Burst Concurrency Comparison (Peak Load Test)

We tested both databases at 100 simultaneous requests—the point just below the host's instability—to measure their raw concurrent reliability.

| Metric | MySQL (c=100 Burst) | SQLite (c=100 Burst) |
| :--- | :--- | :--- |
| **Successful Writes** | **100** | 88 |
| **Failed/Errored** | 0 | 12 |
| **Total Test Time** | **1.080 seconds** | 2.693 seconds |
| **Failure Mode** | N/A | High Latency (1238ms - 1758ms) |

**Analysis of Burst Failure:**
The $\mathbf{12}$ SQLite failures were caused by the database's required **file-locking mechanism**. When 100 threads tried to write to the single `.sqlite` file at the same time, threads were forced into a queue. The waiting time for the thread to acquire and release the lock exceeded the $\mathbf{1000\text{ms}}$ latency limit, resulting in a system-level failure. MySQL's client-server architecture handles these concurrent connections much faster.

---

## 3. Sustained Throughput Comparison (Real-World Load)

To simulate more realistic, sustained traffic (100 requests staggered over $\approx 5$ seconds), we measured the sustainable writes per second (WPS).

| Metric | MySQL (Sustained) | SQLite (Sustained) |
| :--- | :--- | :--- |
| **Successful Writes** | **100** ($\mathbf{100\%}$ Reliability) | 94 ($\mathbf{94\%}$ Reliability) |
| **Total Test Time** | **6.176 seconds** | 7.593 seconds |
| **Average Throughput**| **16.19 writes/second** | 12.38 writes/second |
| **Failure Samples** | N/A | 6 failures due to High Latency |

**Analysis of Sustained Performance:**
Even when traffic was deliberately spread out, SQLite's file-locking limitation prevented it from achieving $100\%$ reliability. The small delays were not enough to eliminate the queuing, resulting in a sustained throughput that is **30% lower** than MySQL.

---

## 4. Final Recommendation

Based on the empirical data, the choice is clear:

### 🥇 Recommended Solution: MySQL

MySQL proved to be $\mathbf{100\%}$ stable and significantly faster than SQLite under both peak burst and sustained concurrent write loads. It is the most robust solution for handling the volume of traffic your current hosting environment can support.

### 🚫 Avoided Solution: SQLite

While SQLite offers simplicity, its fundamental weakness—single-file locking—translates directly into a performance and reliability degradation for web applications with concurrent write requirements on this host.

**Long-Term Consideration:**
If traffic volume grows beyond $\mathbf{100}$ sustained concurrent users, the only effective solution will be to upgrade the hosting plan to increase the Web Host's PHP Process Limit. Until then, MySQL provides the highest achievable performance ceiling.