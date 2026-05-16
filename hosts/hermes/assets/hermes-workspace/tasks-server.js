import { jsxs, jsx, Fragment } from "react/jsx-runtime";
import { u as usePageTitle } from "./use-page-title-DxzhUrGi.js";
import { useState, useEffect, useMemo, useCallback } from "react";
import { useSearch } from "@tanstack/react-router";
import { useQueryClient, useQuery, keepPreviousData, useMutation } from "@tanstack/react-query";
import { motion, AnimatePresence } from "motion/react";
import { HugeiconsIcon } from "@hugeicons/react";
import { RefreshIcon, Add01Icon, CheckListIcon } from "@hugeicons/core-free-icons";
import { c as cn, D as DialogRoot, b as DialogContent, d as DialogTitle, e as DialogDescription, B as Button, t as toast } from "./router-DxziTUUJ.js";
import "react-dom";
import "@base-ui/react/merge-props";
import "@base-ui/react/use-render";
import "class-variance-authority";
import "clsx";
import "tailwind-merge";
import "zustand";
import "@base-ui/react/dialog";
import "@base-ui/react/menu";
import "zustand/middleware";
import "@base-ui/react/input";
import "@base-ui/react/switch";
import "@base-ui/react/tabs";
import "@base-ui/react/alert-dialog";
import "@base-ui/react/collapsible";
import "@base-ui/react/scroll-area";
import "@base-ui/react/tooltip";
import "shiki";
import "marked";
import "react-markdown";
import "remark-breaks";
import "remark-gfm";
import "@base-ui/react/preview-card";
import "@base-ui/react/autocomplete";
import "react-joyride";
import "zod";
import "node:os";
import "node:path";
import "node:fs/promises";
import "yaml";
import "node:crypto";
import "node:fs";
import "node:child_process";
import "node:url";
import "node:events";
import "node:util";
import "node:dns/promises";
const HERMES_BASE = "/api/hermes-tasks";
const CLAUDE_BASE = "/api/claude-tasks";
let _resolved = null;
let _resolving = null;
async function probeBackend(base) {
  try {
    const res = await fetch(base, { signal: AbortSignal.timeout(3e3) });
    if (!res.ok) return -1;
    const data = await res.json();
    return Array.isArray(data.tasks) ? data.tasks.length : -1;
  } catch {
    return -1;
  }
}
async function resolveBackend() {
  if (_resolved) return _resolved;
  if (_resolving) return _resolving;
  _resolving = (async () => {
    const [hermesCount, claudeCount] = await Promise.all([
      probeBackend(HERMES_BASE),
      probeBackend(CLAUDE_BASE)
    ]);
    const useHermes = hermesCount > claudeCount;
    _resolved = {
      base: useHermes ? HERMES_BASE : CLAUDE_BASE,
      assigneesBase: useHermes ? "/api/hermes-tasks-assignees" : "/api/claude-tasks-assignees",
      backend: useHermes ? "hermes" : "claude"
    };
    return _resolved;
  })();
  return _resolving;
}
async function fetchAssignees() {
  const { assigneesBase } = await resolveBackend();
  const res = await fetch(assigneesBase);
  if (!res.ok) return { assignees: [], humanReviewer: null };
  return res.json();
}
async function fetchTasks(params) {
  const { base } = await resolveBackend();
  const q = new URLSearchParams();
  if (params?.column) q.set("column", params.column);
  if (params?.assignee) q.set("assignee", params.assignee);
  if (params?.priority) q.set("priority", params.priority);
  if (params?.include_done) q.set("include_done", "true");
  const url = q.toString() ? `${base}?${q}` : base;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch tasks: ${res.status}`);
  const data = await res.json();
  return data.tasks ?? [];
}
async function createTask(input) {
  const { base } = await resolveBackend();
  const res = await fetch(base, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input)
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.detail || `Failed to create task: ${res.status}`);
  }
  return (await res.json()).task;
}
async function updateTask(taskId, input) {
  const { base } = await resolveBackend();
  const res = await fetch(`${base}/${taskId}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input)
  });
  if (!res.ok) throw new Error(`Failed to update task: ${res.status}`);
  return (await res.json()).task;
}
async function deleteTask(taskId) {
  const { base } = await resolveBackend();
  const res = await fetch(`${base}/${taskId}`, { method: "DELETE" });
  if (!res.ok) throw new Error(`Failed to delete task: ${res.status}`);
}
async function moveTask(taskId, column, movedBy = "user") {
  const { base } = await resolveBackend();
  const res = await fetch(`${base}/${taskId}?action=move`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ column, moved_by: movedBy })
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.detail || `Failed to move task: ${res.status}`);
  }
  return (await res.json()).task;
}
const COLUMN_LABELS = {
  backlog: "Triage",
  todo: "Ready",
  in_progress: "Running",
  review: "Review",
  blocked: "Blocked",
  done: "Done",
  deleted: "Deleted"
};
const COLUMN_ORDER = ["backlog", "todo", "in_progress", "review", "blocked", "done"];
const PRIORITY_COLORS = {
  high: "#ef4444",
  medium: "#f97316",
  low: "#6b7280"
};
const COLUMN_COLORS = {
  backlog: "#6b7280",
  todo: "#3b82f6",
  in_progress: "#f97316",
  review: "#a855f7",
  blocked: "#ef4444",
  done: "#22c55e",
  deleted: "#374151"
};
function isOverdue(task) {
  if (!task.due_date) return false;
  const [year, month, day] = task.due_date.split("-").map(Number);
  const due = new Date(year, month - 1, day);
  const today = /* @__PURE__ */ new Date();
  today.setHours(0, 0, 0, 0);
  return due < today;
}
function formatTaskAssigneeLabel(assignee, assigneeLabels) {
  const resolvedLabel = assignee ? assigneeLabels[assignee] ?? assignee : "Unassigned";
  return `Assignee: ${resolvedLabel}`;
}
function TaskCard({ task, assigneeLabels = {}, onClick, onDragStart, isDragging }) {
  const overdue = isOverdue(task);
  const priorityColor = PRIORITY_COLORS[task.priority];
  const visibleTags = task.tags.slice(0, 2);
  const extraTagCount = task.tags.length - 2;
  const assigneeLabel = formatTaskAssigneeLabel(task.assignee, assigneeLabels);
  return /* @__PURE__ */ jsxs(
    "div",
    {
      draggable: true,
      onDragStart,
      onClick,
      className: cn(
        "relative rounded-lg border p-3 cursor-pointer transition-all select-none",
        "bg-[var(--theme-card)] border-[var(--theme-border)]",
        "hover:border-[var(--theme-accent)]",
        isDragging ? "opacity-40 rotate-1 shadow-2xl" : "hover:shadow-[0_4px_16px_rgba(0,0,0,0.35)]"
      ),
      style: { borderLeftWidth: 3, borderLeftColor: priorityColor },
      children: [
        /* @__PURE__ */ jsx(
          "span",
          {
            className: "absolute top-2.5 right-2.5 w-2 h-2 rounded-full shrink-0",
            style: { background: priorityColor },
            title: `Priority: ${task.priority}`
          }
        ),
        /* @__PURE__ */ jsx("p", { className: "text-sm font-medium text-[var(--theme-text)] leading-snug mb-1 line-clamp-2 pr-4", children: task.title }),
        task.description && /* @__PURE__ */ jsx("p", { className: "text-xs text-[var(--theme-muted)] line-clamp-2 mb-2", children: task.description }),
        /* @__PURE__ */ jsxs("div", { className: "flex items-center justify-between gap-2 mt-2 flex-wrap", children: [
          /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-1.5 flex-wrap", children: [
            /* @__PURE__ */ jsx("span", { className: "text-[10px] px-1.5 py-0.5 rounded-md bg-[var(--theme-hover)] text-[var(--theme-muted)]", children: assigneeLabel }),
            visibleTags.map((tag) => /* @__PURE__ */ jsx(
              "span",
              {
                className: "text-[10px] px-1.5 py-0.5 rounded-md bg-[var(--theme-hover)] text-[var(--theme-muted)]",
                children: tag
              },
              tag
            )),
            extraTagCount > 0 && /* @__PURE__ */ jsxs("span", { className: "text-[10px] px-1.5 py-0.5 rounded-md bg-[var(--theme-hover)] text-[var(--theme-muted)]", children: [
              "+",
              extraTagCount,
              " more"
            ] })
          ] }),
          task.due_date && /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-1 text-[10px] tabular-nums", children: [
            overdue && /* @__PURE__ */ jsxs(Fragment, { children: [
              /* @__PURE__ */ jsx("span", { className: "w-1.5 h-1.5 rounded-full bg-red-400 shrink-0" }),
              /* @__PURE__ */ jsx("span", { className: "text-red-400 font-semibold", children: "Overdue" }),
              /* @__PURE__ */ jsx("span", { className: "text-[var(--theme-muted)] mx-0.5", children: "·" })
            ] }),
            /* @__PURE__ */ jsx("span", { className: overdue ? "text-red-400 font-semibold" : "text-[var(--theme-muted)]", children: (() => {
              const [y, m, d] = task.due_date.split("-").map(Number);
              return new Date(y, m - 1, d).toLocaleDateString("en-US", { month: "short", day: "numeric" });
            })() })
          ] })
        ] })
      ]
    }
  );
}
function TaskDialog({ open, onOpenChange, task, defaultColumn, assignees, onSubmit, isSubmitting }) {
  const isEdit = Boolean(task);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [column, setColumn] = useState(defaultColumn ?? "backlog");
  const [priority, setPriority] = useState("medium");
  const [assignee, setAssignee] = useState("");
  const [tags, setTags] = useState("");
  const [dueDate, setDueDate] = useState("");
  useEffect(() => {
    if (task) {
      setTitle(task.title);
      setDescription(task.description);
      setColumn(task.column);
      setPriority(task.priority);
      setAssignee(task.assignee ?? "");
      setTags(task.tags.join(", "));
      setDueDate(task.due_date ?? "");
    } else {
      setTitle("");
      setDescription("");
      setColumn(defaultColumn ?? "backlog");
      setPriority("medium");
      setAssignee("");
      setTags("");
      setDueDate("");
    }
  }, [task, open, defaultColumn]);
  async function handleSubmit(e) {
    e.preventDefault();
    if (!title.trim()) return;
    await onSubmit({
      title: title.trim(),
      description: description.trim(),
      column,
      priority,
      assignee: assignee || null,
      tags: tags.split(",").map((t) => t.trim()).filter(Boolean),
      due_date: dueDate || null
    });
  }
  const inputClass = cn(
    "w-full rounded-lg border px-3 py-2 text-sm",
    "bg-[var(--theme-input)] border-[var(--theme-border)] text-[var(--theme-text)]",
    "focus:outline-none focus:ring-1 focus:ring-[var(--theme-accent)]",
    "placeholder:text-[var(--theme-muted)]"
  );
  const labelClass = "block text-xs font-medium text-[var(--theme-muted)] mb-1";
  return /* @__PURE__ */ jsx(DialogRoot, { open, onOpenChange, children: /* @__PURE__ */ jsxs(DialogContent, { className: "w-[min(520px,95vw)] border-[var(--theme-border)] bg-[var(--theme-bg)] overflow-hidden", children: [
    /* @__PURE__ */ jsx("div", { className: "h-[3px] w-full", style: { background: "var(--theme-accent)" } }),
    /* @__PURE__ */ jsxs("div", { className: "p-5", children: [
      /* @__PURE__ */ jsx(DialogTitle, { className: "text-base font-semibold text-[var(--theme-text)] mb-1", children: isEdit ? "Edit Task" : "New Task" }),
      /* @__PURE__ */ jsx(DialogDescription, { className: "text-xs text-[var(--theme-muted)] mb-4", children: isEdit ? "Update the task details below." : "Fill in the details for your new task." }),
      /* @__PURE__ */ jsxs("form", { onSubmit: handleSubmit, className: "space-y-3", children: [
        /* @__PURE__ */ jsxs("div", { children: [
          /* @__PURE__ */ jsx("label", { className: labelClass, children: "Title *" }),
          /* @__PURE__ */ jsx(
            "input",
            {
              className: inputClass,
              value: title,
              onChange: (e) => setTitle(e.target.value),
              placeholder: "What needs to be done?",
              required: true,
              autoFocus: true
            }
          )
        ] }),
        /* @__PURE__ */ jsxs("div", { children: [
          /* @__PURE__ */ jsx("label", { className: labelClass, children: "Description" }),
          /* @__PURE__ */ jsx(
            "textarea",
            {
              className: cn(inputClass, "resize-none"),
              rows: 3,
              value: description,
              onChange: (e) => setDescription(e.target.value),
              placeholder: "Optional details..."
            }
          )
        ] }),
        /* @__PURE__ */ jsxs("div", { className: "grid grid-cols-2 gap-3", children: [
          /* @__PURE__ */ jsxs("div", { children: [
            /* @__PURE__ */ jsx("label", { className: labelClass, children: "Column" }),
            /* @__PURE__ */ jsx(
              "select",
              {
                className: inputClass,
                style: { colorScheme: "dark" },
                value: column,
                onChange: (e) => setColumn(e.target.value),
                children: COLUMN_ORDER.map((col) => /* @__PURE__ */ jsx("option", { value: col, children: COLUMN_LABELS[col] }, col))
              }
            )
          ] }),
          /* @__PURE__ */ jsxs("div", { children: [
            /* @__PURE__ */ jsx("label", { className: labelClass, children: "Priority" }),
            /* @__PURE__ */ jsxs(
              "select",
              {
                className: inputClass,
                style: { colorScheme: "dark" },
                value: priority,
                onChange: (e) => setPriority(e.target.value),
                children: [
                  /* @__PURE__ */ jsx("option", { value: "high", children: "High" }),
                  /* @__PURE__ */ jsx("option", { value: "medium", children: "Medium" }),
                  /* @__PURE__ */ jsx("option", { value: "low", children: "Low" })
                ]
              }
            )
          ] })
        ] }),
        /* @__PURE__ */ jsxs("div", { className: "grid grid-cols-2 gap-3", children: [
          /* @__PURE__ */ jsxs("div", { children: [
            /* @__PURE__ */ jsx("label", { className: labelClass, children: "Assignee" }),
            /* @__PURE__ */ jsxs(
              "select",
              {
                className: inputClass,
                style: { colorScheme: "dark" },
                value: assignee,
                onChange: (e) => setAssignee(e.target.value),
                children: [
                  /* @__PURE__ */ jsx("option", { value: "", children: "Unassigned" }),
                  assignees.map(({ id, label }) => /* @__PURE__ */ jsx("option", { value: id, children: label }, id))
                ]
              }
            ),
            /* @__PURE__ */ jsx("p", { className: "mt-1 text-[10px] text-[var(--theme-muted)]", children: "Assignee is separate from status. Dragging a card changes its column only." })
          ] }),
          /* @__PURE__ */ jsxs("div", { children: [
            /* @__PURE__ */ jsx("label", { className: labelClass, children: "Due Date" }),
            /* @__PURE__ */ jsx(
              "input",
              {
                type: "date",
                className: inputClass,
                style: { colorScheme: "dark" },
                value: dueDate,
                onChange: (e) => setDueDate(e.target.value)
              }
            )
          ] })
        ] }),
        /* @__PURE__ */ jsxs("div", { children: [
          /* @__PURE__ */ jsx("label", { className: labelClass, children: "Tags (comma-separated)" }),
          /* @__PURE__ */ jsx(
            "input",
            {
              className: inputClass,
              value: tags,
              onChange: (e) => setTags(e.target.value),
              placeholder: "frontend, bug, research"
            }
          )
        ] }),
        /* @__PURE__ */ jsxs("div", { className: "flex items-center justify-between pt-2", children: [
          /* @__PURE__ */ jsx("p", { className: "text-[10px] text-[var(--theme-muted)]", children: "Press Esc to cancel" }),
          /* @__PURE__ */ jsxs("div", { className: "flex gap-2", children: [
            /* @__PURE__ */ jsx(
              Button,
              {
                type: "button",
                variant: "ghost",
                size: "sm",
                onClick: () => onOpenChange(false),
                disabled: isSubmitting,
                children: "Cancel"
              }
            ),
            /* @__PURE__ */ jsx(
              Button,
              {
                type: "submit",
                size: "sm",
                disabled: isSubmitting || !title.trim(),
                style: { background: "var(--theme-accent)", color: "white" },
                children: isSubmitting ? "Saving..." : isEdit ? "Save Changes" : "Create Task"
              }
            )
          ] })
        ] })
      ] })
    ] })
  ] }) });
}
const QUERY_KEY = ["claude", "tasks"];
const ASSIGNEES_KEY = ["claude", "tasks", "assignees"];
const TASKS_BOARD_HELP_TEXT = "Drag cards to change status. Open a card to set assignee and due date.";
function SkeletonCard() {
  return /* @__PURE__ */ jsxs("div", { className: "rounded-lg border border-[var(--theme-border)] bg-[var(--theme-card)] p-3 animate-pulse", children: [
    /* @__PURE__ */ jsx("div", { className: "h-3.5 bg-[var(--theme-hover)] rounded w-3/4 mb-2" }),
    /* @__PURE__ */ jsx("div", { className: "h-2.5 bg-[var(--theme-hover)] rounded w-full mb-1" }),
    /* @__PURE__ */ jsx("div", { className: "h-2.5 bg-[var(--theme-hover)] rounded w-2/3 mb-3" }),
    /* @__PURE__ */ jsxs("div", { className: "flex gap-1.5", children: [
      /* @__PURE__ */ jsx("div", { className: "h-4 w-12 bg-[var(--theme-hover)] rounded" }),
      /* @__PURE__ */ jsx("div", { className: "h-4 w-10 bg-[var(--theme-hover)] rounded" })
    ] })
  ] });
}
function TasksScreen() {
  const queryClient = useQueryClient();
  const [showCreate, setShowCreate] = useState(false);
  const [createColumn, setCreateColumn] = useState("backlog");
  const [editingTask, setEditingTask] = useState(null);
  const [draggingId, setDraggingId] = useState(null);
  const [dragOverColumn, setDragOverColumn] = useState(null);
  const [showDone, setShowDone] = useState(false);
  const search = useSearch({ from: "/tasks" });
  const initialAssignee = typeof search.assignee === "string" ? search.assignee : null;
  const [assigneeFilter, setAssigneeFilter] = useState(initialAssignee);
  const tasksQuery = useQuery({
    queryKey: [...QUERY_KEY, showDone],
    queryFn: () => fetchTasks({ include_done: showDone }),
    refetchInterval: 3e4,
    placeholderData: keepPreviousData
  });
  const assigneesQuery = useQuery({
    queryKey: ASSIGNEES_KEY,
    queryFn: fetchAssignees,
    staleTime: 5 * 6e4
    // profiles don't change often
  });
  const assignees = assigneesQuery.data?.assignees ?? [];
  const humanReviewer = assigneesQuery.data?.humanReviewer ?? null;
  const assigneeLabels = useMemo(() => {
    const map = {};
    for (const a of assignees) map[a.id] = a.label;
    return map;
  }, [assignees]);
  const tasks = tasksQuery.data ?? [];
  const tasksByColumn = useMemo(() => {
    const map = {
      backlog: [],
      todo: [],
      in_progress: [],
      review: [],
      blocked: [],
      done: []
    };
    for (const t of tasks) {
      if (assigneeFilter && t.assignee !== assigneeFilter) continue;
      if (map[t.column]) map[t.column].push(t);
    }
    for (const col of COLUMN_ORDER) {
      map[col].sort((a, b) => a.position - b.position);
    }
    return map;
  }, [tasks, assigneeFilter]);
  const stats = useMemo(() => {
    const total = tasks.length;
    const running = tasks.filter((t) => t.column === "in_progress").length;
    const blocked = tasks.filter((t) => t.column === "blocked").length;
    const done = tasks.filter((t) => t.column === "done").length;
    const overdue = tasks.filter((t) => isOverdue(t) && t.column !== "done").length;
    const completion = total > 0 ? Math.round(done / total * 100) : 0;
    return { total, running, blocked, done, overdue, completion };
  }, [tasks]);
  const invalidate = useCallback(() => {
    void queryClient.invalidateQueries({ queryKey: QUERY_KEY });
  }, [queryClient]);
  const createMutation = useMutation({
    mutationFn: createTask,
    onSuccess: () => {
      invalidate();
      toast("Task created");
      setShowCreate(false);
    },
    onError: (e) => toast(e instanceof Error ? e.message : "Failed to create task", { type: "error" })
  });
  const updateMutation = useMutation({
    mutationFn: ({ id, input }) => updateTask(id, input),
    onSuccess: () => {
      invalidate();
      toast("Task updated");
      setEditingTask(null);
    },
    onError: (e) => toast(e instanceof Error ? e.message : "Failed to update task", { type: "error" })
  });
  useMutation({
    mutationFn: deleteTask,
    onSuccess: () => {
      invalidate();
      toast("Task deleted");
    },
    onError: (e) => toast(e instanceof Error ? e.message : "Failed to delete task", { type: "error" })
  });
  const moveMutation = useMutation({
    mutationFn: ({ id, column }) => moveTask(id, column, "user"),
    onSuccess: () => invalidate(),
    onError: (e) => toast(e instanceof Error ? e.message : "Failed to move task", { type: "error" })
  });
  function handleDragStart(e, taskId) {
    e.dataTransfer.setData("text/plain", taskId);
    setDraggingId(taskId);
  }
  function handleDragOver(e, col) {
    e.preventDefault();
    setDragOverColumn(col);
  }
  function handleDrop(e, targetColumn) {
    e.preventDefault();
    const taskId = e.dataTransfer.getData("text/plain");
    const task = tasks.find((t) => t.id === taskId);
    if (!task || task.column === targetColumn) {
      setDraggingId(null);
      setDragOverColumn(null);
      return;
    }
    if (targetColumn === "done" && humanReviewer) {
      toast(`Only ${humanReviewer} can mark tasks as done`, { type: "error" });
      setDraggingId(null);
      setDragOverColumn(null);
      return;
    }
    moveMutation.mutate({ id: taskId, column: targetColumn });
    setDraggingId(null);
    setDragOverColumn(null);
  }
  function handleDragEnd() {
    setDraggingId(null);
    setDragOverColumn(null);
  }
  const visibleColumns = showDone ? COLUMN_ORDER : COLUMN_ORDER.filter((c) => c !== "done");
  const colMaxWidth = Math.floor(1200 / visibleColumns.length);
  return /* @__PURE__ */ jsx("div", { className: "min-h-full overflow-y-auto bg-surface text-ink", children: /* @__PURE__ */ jsxs("div", { className: "mx-auto flex w-full max-w-[1200px] flex-col gap-5 px-4 py-6 pb-[calc(var(--tabbar-h,80px)+1.5rem)] sm:px-6 lg:px-8", children: [
    /* @__PURE__ */ jsxs("header", { className: "rounded-2xl border border-primary-200 bg-primary-50/85 p-4 backdrop-blur-xl", children: [
      /* @__PURE__ */ jsxs("div", { className: "flex items-center justify-between", children: [
        /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-3 min-w-0", children: [
          /* @__PURE__ */ jsx("h1", { className: "text-2xl font-medium text-ink", children: "Tasks" }),
          assigneeFilter && /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-2 text-xs text-[var(--theme-muted)]", children: [
            /* @__PURE__ */ jsxs("span", { children: [
              "Filtered by: ",
              /* @__PURE__ */ jsx("span", { className: "capitalize", style: { color: "#f59e0b" }, children: assigneeFilter })
            ] }),
            /* @__PURE__ */ jsx(
              "button",
              {
                type: "button",
                onClick: () => setAssigneeFilter(null),
                className: "text-[var(--theme-muted)] hover:text-[var(--theme-text)] transition-colors",
                children: "✕ Clear"
              }
            )
          ] }),
          /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-2 text-xs text-[var(--theme-muted)] flex-wrap", children: [
            /* @__PURE__ */ jsxs("span", { children: [
              stats.total,
              " total"
            ] }),
            /* @__PURE__ */ jsx("span", { className: "hidden sm:inline", children: "·" }),
            /* @__PURE__ */ jsxs("span", { className: "hidden sm:inline", children: [
              stats.running,
              " running"
            ] }),
            stats.blocked > 0 && /* @__PURE__ */ jsxs(Fragment, { children: [
              /* @__PURE__ */ jsx("span", { className: "hidden sm:inline", children: "·" }),
              /* @__PURE__ */ jsxs("span", { className: "text-red-400", children: [
                stats.blocked,
                " blocked"
              ] })
            ] }),
            stats.overdue > 0 && /* @__PURE__ */ jsxs(Fragment, { children: [
              /* @__PURE__ */ jsx("span", { children: "·" }),
              /* @__PURE__ */ jsxs("span", { className: "text-red-400", children: [
                stats.overdue,
                " overdue"
              ] })
            ] }),
            /* @__PURE__ */ jsx("span", { className: "hidden sm:inline", children: "·" }),
            /* @__PURE__ */ jsxs("span", { className: "hidden sm:inline", children: [
              stats.completion,
              "% done"
            ] })
          ] })
        ] }),
        /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-2 shrink-0", children: [
          /* @__PURE__ */ jsx(
            "button",
            {
              onClick: () => setShowDone((v) => !v),
              className: cn(
                "text-xs px-2.5 py-1 rounded-lg border transition-colors",
                showDone ? "border-[var(--theme-accent)] text-[var(--theme-accent)] bg-[var(--theme-hover)]" : "border-[var(--theme-border)] text-[var(--theme-muted)] hover:text-[var(--theme-text)] hover:border-[var(--theme-accent)]"
              ),
              children: showDone ? "Hide Done" : "Show Done"
            }
          ),
          /* @__PURE__ */ jsx(
            "button",
            {
              onClick: invalidate,
              className: "rounded-lg p-1.5 transition-colors hover:bg-[var(--theme-hover)]",
              title: "Refresh",
              children: /* @__PURE__ */ jsx(HugeiconsIcon, { icon: RefreshIcon, size: 16, className: "text-[var(--theme-muted)]" })
            }
          ),
          /* @__PURE__ */ jsxs(
            "button",
            {
              onClick: () => {
                setCreateColumn("backlog");
                setShowCreate(true);
              },
              className: "flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium text-white transition-opacity hover:opacity-90",
              style: { background: "var(--theme-accent)" },
              children: [
                /* @__PURE__ */ jsx(HugeiconsIcon, { icon: Add01Icon, size: 14 }),
                "New Task"
              ]
            }
          )
        ] })
      ] }),
      /* @__PURE__ */ jsx("p", { className: "mt-3 text-xs text-[var(--theme-muted)]", children: TASKS_BOARD_HELP_TEXT })
    ] }),
    /* @__PURE__ */ jsx(
      "div",
      {
        className: "mx-auto flex w-full max-w-[1200px] flex-1 gap-3 overflow-x-auto overflow-y-hidden p-4 min-h-0",
        style: { boxShadow: "inset 0 8px 24px rgba(0,0,0,0.2)" },
        children: visibleColumns.map((col) => {
          const colTasks = tasksByColumn[col];
          const colColor = COLUMN_COLORS[col];
          const isDragOver = dragOverColumn === col;
          return /* @__PURE__ */ jsxs(
            "div",
            {
              className: cn(
                "flex flex-col rounded-xl border min-w-[180px] w-full shrink-0 flex-1",
                "bg-[var(--theme-card)] border-[var(--theme-border)]",
                "transition-colors shadow-[0_2px_12px_rgba(0,0,0,0.25)]",
                isDragOver && "border-[var(--theme-accent)] bg-[var(--theme-hover)]"
              ),
              style: { maxWidth: colMaxWidth },
              onDragOver: (e) => handleDragOver(e, col),
              onDrop: (e) => handleDrop(e, col),
              onDragLeave: () => setDragOverColumn(null),
              children: [
                /* @__PURE__ */ jsxs(
                  "div",
                  {
                    className: "flex items-center justify-between px-3 py-2.5 border-b border-[var(--theme-border)] rounded-t-xl",
                    style: { borderTopWidth: 2, borderTopColor: colColor, borderTopStyle: "solid" },
                    children: [
                      /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-2", children: [
                        /* @__PURE__ */ jsx("span", { className: "w-2 h-2 rounded-full shrink-0", style: { background: colColor } }),
                        /* @__PURE__ */ jsx("span", { className: "text-xs font-semibold text-[var(--theme-text)]", children: COLUMN_LABELS[col] }),
                        /* @__PURE__ */ jsxs("span", { className: "text-xs text-[var(--theme-muted)]", children: [
                          "(",
                          tasksQuery.isFetching && tasksQuery.data === void 0 ? "…" : colTasks.length,
                          ")"
                        ] })
                      ] }),
                      /* @__PURE__ */ jsx(
                        "button",
                        {
                          onClick: () => {
                            setCreateColumn(col);
                            setShowCreate(true);
                          },
                          className: "rounded p-0.5 hover:bg-[var(--theme-hover)] transition-colors",
                          title: `Add to ${COLUMN_LABELS[col]}`,
                          children: /* @__PURE__ */ jsx(HugeiconsIcon, { icon: Add01Icon, size: 14, className: "text-[var(--theme-muted)]" })
                        }
                      )
                    ]
                  }
                ),
                /* @__PURE__ */ jsx("div", { className: "flex flex-col gap-2 p-2 flex-1 overflow-y-auto", children: tasksQuery.isError ? /* @__PURE__ */ jsxs(
                  motion.div,
                  {
                    initial: { opacity: 0 },
                    animate: { opacity: 1 },
                    className: "flex flex-col items-center justify-center py-8 gap-2 text-red-400",
                    children: [
                      /* @__PURE__ */ jsx("p", { className: "text-xs font-medium", children: "Failed to load tasks" }),
                      /* @__PURE__ */ jsx(
                        "button",
                        {
                          onClick: () => tasksQuery.refetch(),
                          className: "text-xs text-[var(--theme-accent)] hover:underline",
                          children: "Retry"
                        }
                      )
                    ]
                  },
                  "error"
                ) : tasksQuery.isLoading ? /* @__PURE__ */ jsxs(Fragment, { children: [
                  /* @__PURE__ */ jsx(SkeletonCard, {}),
                  /* @__PURE__ */ jsx(SkeletonCard, {}),
                  /* @__PURE__ */ jsx(SkeletonCard, {})
                ] }) : /* @__PURE__ */ jsx(AnimatePresence, { initial: false, children: colTasks.length === 0 ? /* @__PURE__ */ jsxs(
                  motion.div,
                  {
                    initial: { opacity: 0 },
                    animate: { opacity: 1 },
                    exit: { opacity: 0 },
                    className: "flex flex-col items-center justify-center py-8 gap-2 text-[var(--theme-muted)] opacity-60",
                    children: [
                      /* @__PURE__ */ jsx(HugeiconsIcon, { icon: CheckListIcon, size: 22 }),
                      /* @__PURE__ */ jsx("p", { className: "text-xs font-medium", children: "No tasks" }),
                      /* @__PURE__ */ jsx("p", { className: "text-[10px]", children: "Drop here or click + to add" })
                    ]
                  },
                  "empty"
                ) : colTasks.map((task) => /* @__PURE__ */ jsx(
                  motion.div,
                  {
                    layout: true,
                    initial: { opacity: 0, y: 6 },
                    animate: { opacity: 1, y: 0 },
                    exit: { opacity: 0, y: -6 },
                    onDragEnd: handleDragEnd,
                    children: /* @__PURE__ */ jsx(
                      TaskCard,
                      {
                        task,
                        assigneeLabels,
                        isDragging: draggingId === task.id,
                        onDragStart: (e) => handleDragStart(e, task.id),
                        onClick: () => setEditingTask(task)
                      }
                    )
                  },
                  task.id
                )) }) })
              ]
            },
            col
          );
        })
      }
    ),
    /* @__PURE__ */ jsx(
      TaskDialog,
      {
        open: showCreate,
        onOpenChange: setShowCreate,
        defaultColumn: createColumn,
        assignees,
        isSubmitting: createMutation.isPending,
        onSubmit: async (input) => {
          await createMutation.mutateAsync(input);
        }
      }
    ),
    /* @__PURE__ */ jsx(
      TaskDialog,
      {
        open: editingTask !== null,
        onOpenChange: (open) => {
          if (!open) setEditingTask(null);
        },
        task: editingTask,
        assignees,
        isSubmitting: updateMutation.isPending,
        onSubmit: async (input) => {
          if (!editingTask) return;
          await updateMutation.mutateAsync({ id: editingTask.id, input });
        }
      }
    )
  ] }) });
}
function TasksRoute() {
  usePageTitle("Tasks");
  return /* @__PURE__ */ jsx(TasksScreen, {});
}
export {
  TasksRoute as component
};
