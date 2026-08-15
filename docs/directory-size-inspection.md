# Directory size inspection

Sidebar size inspection is a best-effort, read-only operation. It runs in the
`FileSystemOperationScheduler` inspection category, below probes and pane loads.
The category permits one running traversal and four queued traversals by default;
the scheduler's global limits still apply. A saturated inspection or global queue
returns an unavailable result to the UI rather than performing work elsewhere.

`DirectorySizingService` validates the selected root with
`SandboxFileAccessPolicy` before scheduling it and retains any security-scoped
access for the operation. Symbolic links are not followed and contribute zero
bytes. Hidden descendants are included.

Inaccessible or concurrently disappearing descendants are skipped and make the
result **partial**. The sidebar labels such a value “At least …”; it never displays
the accumulated lower bound as an exact total. Failure to inspect the root, policy
rejection, and scheduler saturation display “Unavailable”.

Cancellation is checked between descendants. A synchronous filesystem call that
is already stalled cannot be forcefully interrupted: it continues to occupy its
inspection and global scheduler slots until the operating system returns. This
prevents repeated requests to a stalled volume from creating unbounded threads.
Cancelled and superseded sidebar requests do not update the current selection.
