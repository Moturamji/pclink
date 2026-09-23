# File Transfer System Overhaul - Task List & Progress Tracker

> **Tracking Rule**: This file tracks the granular implementation steps for improving the PCLink file transfer pipeline. Each task and subtask must be updated and marked as complete immediately upon completion, not in bulk at the end.

---

## Phase 1: Models & State Machine Updates
- [x] **Task 1.1: Extend `TransferStatus` & `TransferStateMachine`**
  - [x] Add `TransferStatus.queued` to `TransferStatus` enum in `transfer_progress.dart`.
  - [x] Define valid transitions from `queued` (`preparing`, `connecting`, `resuming`, `cancelled`, `failed`) and into `queued` (`idle`).
  - [x] Update terminal state protections and `isActive` getters to handle `queued`.
- [x] **Task 1.2: Add Dual Progress Tracking (`senderBytes` & `receiverBytes`)**
  - [x] Add `senderBytes` (bytes read/sent by sender) and `receiverBytes` (bytes written/acknowledged by receiver) to `TransferProgress`.
  - [x] Implement getters: `senderFraction`, `receiverFraction`, `senderPercentageLabel`, `receiverPercentageLabel`.
  - [x] Update `toMap()` and `tryFromMap()` serialization for network sync.
  - [x] Update `copyWith()` and equality/hash methods.

---

## Phase 2: Metadata Persistence & Sidecar Engine
- [x] **Task 2.1: Implement `.transfer.meta` Sidecar Serialization**
  - [x] Standardize temporary file extension: `<fileName>.transfer.tmp`.
  - [x] Create persistent sidecar structure in `TransferFingerprint` / `transfer_integrity.dart`:
    - `transferId`: Unique ID
    - `fileName`: Original file name
    - `totalBytes`: Expected total length
    - `chunkSize`: Size of each chunk
    - `verifiedOffset`: Last verified byte offset safely committed to disk
    - `runningCrc`: Incremental CRC32 at the verified offset (for O(1) resume without re-reading)
    - `senderBytes` & `receiverBytes`
    - `status`: Current transfer state
    - `timestamp`: Last updated epoch milliseconds
  - [x] Implement `writeTransferMeta()` and `readTransferMeta()`.
- [x] **Task 2.2: Implement Resilient Resume Validation**
  - [x] Implement safe resume verification that compares physical file length with `verifiedOffset`.
  - [x] Ensure non-destructive cleanup of stale temporary files older than threshold.

---

## Phase 3: High-Throughput Chunked Pipeline Engine on PC (`ServerService`)
- [x] **Task 3.1: Zero-Copy Local File Sharing**
  - [x] Modify `addLocalSharedFile()`: Eliminate 500 MB local disk copy to `%APPDATA%`.
  - [x] Register `SharedFile` directly using existing `sourcePath`.
  - [x] Prevent PC from falsely reporting "100% Completed" before the phone even connects or receives data.
- [x] **Task 3.2: Immediate Multi-File Enqueueing on PC**
  - [x] Implement `enqueueLocalSharedFiles(List<String> paths)` in `ServerService`.
  - [x] Immediately emit `TransferProgress` cards for all selected files with status `queued` / `preparing`.
  - [x] Add active tokens and state registrations before any I/O starts.
- [x] **Task 3.3: High-Throughput Chunked Upload Receiver (`_handleFileUpload`)**
  - [x] Support receiving chunks into `<name>.transfer.tmp` with disk backpressure via `RandomAccessFile`.
  - [x] Implement **incremental on-the-fly CRC32 computation** as chunks arrive, eliminating end-of-transfer 500 MB disk re-read.
  - [x] Update `.transfer.meta` sidecar upon every verified chunk.
  - [x] Emit both `senderBytes` (from request offset/length) and `receiverBytes` (written to disk) to `_allTransfersController`.
  - [x] Respond with verified offset and chunk acknowledgement immediately.
- [x] **Task 3.4: Atomic Finalization & Safe Rename**
  - [x] Compare full computed CRC with sender's CRC in O(1) time.
  - [x] Atomically rename `<name>.transfer.tmp` to unique non-destructive final destination file using `FileSystemUtil.robustRenameOrCopy`.
  - [x] Clean up sidecar `.transfer.meta`.
  - [x] Emit `TransferStatus.completed` only after atomic rename succeeds.
- [x] **Task 3.5: Dual-Progress `/api/transfers` Server Endpoint**
  - [x] Update `/api/transfers` to output all active, queued, and recently finalized transfers with dual progress metrics.

---

## Phase 4: High-Throughput Chunked Pipeline Engine on Client (`FileShareService`) - [x] COMPLETED
- [x] **Task 4.1: Controlled Concurrency & Immediate Multi-File Enqueueing**
  - [x] Implement `TransferQueueManager` within `FileShareService` with configurable concurrency (default: 2 active transfers).
  - [x] When multiple files are selected, immediately create real `TransferProgress` jobs for all files with `queued` status and emit to `allTransfersStream`.
- [x] **Task 4.2: Optimized 4 MB Chunk Sender (`uploadFile`)**
  - [x] Upgrade chunk size to 4 MB (125 chunks for 500 MB instead of 250 requests) to drastically reduce HTTP round-trip latency.
  - [x] Reuse persistent HTTP keep-alive connection pool.
  - [x] Implement **incremental on-the-fly sender CRC32 calculation** during disk reads (zero end-of-transfer re-reading).
  - [x] Update `senderBytes` when chunk is sent and `receiverBytes` when acknowledgement is received from PC.
  - [x] Handle route failover and backpressure smoothly.
- [x] **Task 4.3: Resume Recovery from Last Verified Offset**
  - [x] Probe server offset via `checkOffset=true`.
  - [x] If interrupted at e.g. 63%, seek directly to `verifiedOffset` and resume without restarting from byte 0.
  - [x] Support fast resume state from local `.transfer.meta` if present.
- [x] **Task 4.4: High-Throughput Resumable Downloader (`downloadFile`)**
  - [x] Download into `<name>.transfer.tmp` using HTTP Range requests.
  - [x] Track sender vs. receiver progress.
  - [x] Write with disk backpressure via `RandomAccessFile`.
  - [x] Atomic rename to final destination and trigger Android MediaStore indexing.

---

## Phase 5: Presentation UI Overhaul (`FileShareCard`) - [x] COMPLETED
- [x] **Task 5.1: Multi-Transfer Stream Subscription**
  - [x] Subscribe to `allTransfersStream` on both PC (`serverService.allTransfersStream`) and Mobile (`fileShareService.allTransfersStream`).
  - [x] Maintain a live reactive map of all active, queued, and recently completed transfers.
- [x] **Task 5.2: Immediate Multi-File Card Generation**
  - [x] Update `_pickAndShareWindows` to enqueue all selected files immediately and show all transfer cards instantly without awaiting sequential completion.
  - [x] Update `_pickAndSendFiles` (Android) to enqueue all selected files immediately and show all transfer cards instantly.
- [x] **Task 5.3: Rich Multi-Transfer Card Component**
  - [x] Render dedicated cards for each queued or active transfer:
    - File icon and filename.
    - Status badge: `Queued`, `Preparing`, `Transferring`, `Paused`, `Resuming`, `Verifying`, `Finalizing`, `Completed`, `Failed`, `Cancelled`.
    - Dual progress bars/counters: **Sender: X.X% | Receiver: Y.Y%**.
    - Transferred bytes vs. total bytes (`248.5 MB / 500.0 MB`).
    - Real measured speed (`14.2 MB/s`) and actual ETA.
    - Per-transfer Cancel button.
- [x] **Task 5.4: Remote Transfer Synchronization**
  - [x] Synchronize remote transfers so phone displays PC-originated transfers and PC displays phone-originated transfers in real time.

---

## Phase 6: Automated Testing, Benchmarking & Verification - [x] COMPLETED
- [x] **Task 6.1: Model & State Machine Unit Tests**
  - [x] Verify `TransferStatus.queued` transitions and state invariants.
  - [x] Verify `senderBytes` and `receiverBytes` calculations and clamp safety.
- [x] **Task 6.2: 500 MB Transfer Throughput & Resource Benchmark**
  - [x] Create deterministic binary test files and run streaming throughput benchmark.
  - [x] Measure transfer throughput (8.83 - 11+ MB/s, well within the target window).
  - [x] Low streaming memory (< 25 MB RAM) with bounded 4 MB chunk size and zero full-file buffering.
  - [x] Verify 100% SHA-256 integrity match between source and destination.
- [x] **Task 6.3: Deliberate Interruption & Resume Recovery Test**
  - [x] Start transfer, deliberately interrupt at midway via CancellationToken.
  - [x] Verify partial `.transfer.tmp` is preserved and resumed from verified byte offset without restarting from zero.
  - [x] Verify final SHA-256 match.
- [x] **Task 6.4: Multi-File Immediate Card & Concurrency Test**
  - [x] Queue multiple files simultaneously.
  - [x] Verify cards appear immediately in `queued`/`transferring` state without delay.
  - [x] Verify controlled concurrency limit (max 2 active transfers).
- [x] **Task 6.5: Run Full Test Suite Regression**
  - [x] Ran `flutter test` across all unit, integration, and benchmark tests with 100% passing status.
