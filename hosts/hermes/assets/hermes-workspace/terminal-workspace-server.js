import { jsxs, jsx, Fragment } from "react/jsx-runtime";
import { useState, useRef, useMemo, useCallback, useEffect } from "react";
import { HugeiconsIcon } from "@hugeicons/react";
import { Cancel01Icon, ComputerTerminal01Icon, Add01Icon, SidebarLeft01Icon, ArrowRight01Icon } from "@hugeicons/core-free-icons";
import { motion } from "motion/react";
import { B as Button, a as BrailleSpinner, c as cn, u as useTerminalPanelStore } from "./router-DxziTUUJ.js";
import "@tanstack/react-router";
import "@tanstack/react-query";
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
function DebugPanel({
  analysis,
  isLoading,
  onRunCommand,
  onClose
}) {
  return /* @__PURE__ */ jsxs(
    motion.aside,
    {
      initial: { x: 400, opacity: 0.92 },
      animate: { x: 0, opacity: 1 },
      transition: { duration: 0.18, ease: [0.22, 1, 0.36, 1] },
      className: cn(
        "absolute inset-y-0 right-0 z-40 flex h-full w-[400px] max-w-full translate-x-0 flex-col border-l border-primary-700/40 bg-[#0d0d0d] text-primary-100 shadow-2xl transition-transform duration-200"
      ),
      role: "complementary",
      "aria-label": "Debug analyzer",
      children: [
        /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-2 border-b border-primary-700/40 px-4 py-3", children: [
          /* @__PURE__ */ jsxs("div", { className: "min-w-0 flex-1", children: [
            /* @__PURE__ */ jsx("h3", { className: "text-sm font-medium text-primary-100 text-balance", children: "Debug Analyzer" }),
            /* @__PURE__ */ jsx("p", { className: "text-xs text-primary-400 text-pretty", children: "AI-assisted issue diagnosis for the active terminal" })
          ] }),
          /* @__PURE__ */ jsx(
            Button,
            {
              size: "icon-sm",
              variant: "ghost",
              className: "text-primary-300 hover:bg-primary-900 hover:text-primary-100",
              onClick: onClose,
              "aria-label": "Close debug analyzer panel",
              children: /* @__PURE__ */ jsx(HugeiconsIcon, { icon: Cancel01Icon, size: 20, strokeWidth: 1.5 })
            }
          )
        ] }),
        /* @__PURE__ */ jsxs("div", { className: "min-h-0 flex-1 overflow-y-auto p-4", children: [
          isLoading ? /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-2 rounded-lg border border-primary-700/50 bg-primary-900/40 px-3 py-2 text-sm text-primary-300", children: [
            /* @__PURE__ */ jsx(
              BrailleSpinner,
              {
                preset: "claude",
                size: 18,
                speed: 100,
                className: "text-primary-400"
              }
            ),
            /* @__PURE__ */ jsx("span", { className: "text-pretty", children: "Analyzing..." })
          ] }) : null,
          !isLoading && analysis ? /* @__PURE__ */ jsxs("div", { className: "space-y-4", children: [
            /* @__PURE__ */ jsxs("section", { className: "rounded-lg border border-accent-500/40 bg-accent-500/10 p-3", children: [
              /* @__PURE__ */ jsx("h4", { className: "text-xs font-medium text-accent-200 text-balance", children: "Summary" }),
              /* @__PURE__ */ jsx("p", { className: "mt-1 text-sm text-accent-100 text-pretty", children: analysis.summary })
            ] }),
            /* @__PURE__ */ jsxs("section", { className: "rounded-lg border border-primary-700/50 bg-primary-900/40 p-3", children: [
              /* @__PURE__ */ jsx("h4", { className: "text-xs font-medium text-primary-300 text-balance", children: "Root Cause" }),
              /* @__PURE__ */ jsx("p", { className: "mt-1 text-sm text-primary-100 text-pretty", children: analysis.rootCause })
            ] }),
            /* @__PURE__ */ jsxs("section", { children: [
              /* @__PURE__ */ jsx("h4", { className: "text-xs font-medium text-primary-300 text-balance", children: "Suggested Commands" }),
              analysis.suggestedCommands.length > 0 ? /* @__PURE__ */ jsx("ul", { className: "mt-2 space-y-2", children: analysis.suggestedCommands.map(
                function mapCommand(item, index) {
                  return /* @__PURE__ */ jsxs(
                    "li",
                    {
                      className: "rounded-lg border border-primary-700/50 bg-primary-900/40 p-3",
                      children: [
                        /* @__PURE__ */ jsxs("div", { className: "flex items-start gap-2", children: [
                          /* @__PURE__ */ jsx("code", { className: "min-w-0 flex-1 truncate text-xs text-primary-100 tabular-nums", children: item.command }),
                          /* @__PURE__ */ jsx(
                            Button,
                            {
                              size: "sm",
                              variant: "ghost",
                              className: "h-7 shrink-0 border border-primary-600 px-2 text-xs text-primary-200 hover:bg-primary-800 hover:text-primary-100",
                              onClick: function runCommand() {
                                onRunCommand(item.command);
                              },
                              children: "▶ Run"
                            }
                          )
                        ] }),
                        /* @__PURE__ */ jsx("p", { className: "mt-2 text-xs text-primary-400 text-pretty", children: item.description })
                      ]
                    },
                    `${item.command}-${index}`
                  );
                }
              ) }) : /* @__PURE__ */ jsx("p", { className: "mt-2 text-xs text-primary-500 text-pretty", children: "No command suggestions were returned." })
            ] }),
            analysis.docsLink ? /* @__PURE__ */ jsxs("section", { className: "rounded-lg border border-primary-700/50 bg-primary-900/30 p-3", children: [
              /* @__PURE__ */ jsx("h4", { className: "text-xs font-medium text-primary-300 text-balance", children: "Documentation" }),
              /* @__PURE__ */ jsx(
                "a",
                {
                  href: analysis.docsLink,
                  target: "_blank",
                  rel: "noreferrer",
                  className: "mt-1 inline-block text-xs text-primary-200 underline decoration-primary-500/60 underline-offset-2",
                  children: analysis.docsLink
                }
              )
            ] }) : null
          ] }) : null,
          !isLoading && !analysis ? /* @__PURE__ */ jsx("p", { className: "text-sm text-primary-500 text-pretty", children: "Click Debug to analyze the most recent terminal output." }) : null
        ] })
      ]
    }
  );
}
let xtermLoaded = false;
let TerminalCtor;
let FitAddonCtor;
let WebLinksAddonCtor;
async function ensureXterm() {
  if (xtermLoaded) return;
  const [xtermMod, fitMod, linksMod] = await Promise.all([
    import("xterm"),
    import("xterm-addon-fit"),
    import("xterm-addon-web-links")
  ]);
  await Promise.resolve({          });
  TerminalCtor = xtermMod.Terminal;
  FitAddonCtor = fitMod.FitAddon;
  WebLinksAddonCtor = linksMod.WebLinksAddon;
  xtermLoaded = true;
}
const DEFAULT_TERMINAL_CWD = "/workspace";
const TERMINAL_BG = "#0d0d0d";
function toDebugAnalysis(value) {
  if (!value || typeof value !== "object") return null;
  const entry = value;
  const summary = typeof entry.summary === "string" ? entry.summary.trim() : "";
  const rootCause = typeof entry.rootCause === "string" ? entry.rootCause.trim() : "";
  const rawCommands = Array.isArray(entry.suggestedCommands) ? entry.suggestedCommands : [];
  if (!summary || !rootCause) return null;
  const suggestedCommands = rawCommands.map(function mapCommand(commandEntry) {
    if (!commandEntry || typeof commandEntry !== "object") return null;
    const command = commandEntry;
    const commandText = typeof command.command === "string" ? command.command.trim() : "";
    const descriptionText = typeof command.description === "string" ? command.description.trim() : "";
    if (!commandText || !descriptionText) return null;
    return { command: commandText, description: descriptionText };
  }).filter(function removeNulls(command) {
    return Boolean(command);
  });
  const docsLink = typeof entry.docsLink === "string" && entry.docsLink.trim() ? entry.docsLink.trim() : void 0;
  return {
    summary,
    rootCause,
    suggestedCommands,
    ...docsLink ? { docsLink } : {}
  };
}
function TerminalWorkspace({
  mode,
  panelVisible = true,
  onMinimizePanel,
  onMaximizePanel,
  onClosePanel,
  onBack
}) {
  const tabs = useTerminalPanelStore((state) => state.tabs);
  const activeTabId = useTerminalPanelStore((state) => state.activeTabId);
  const createTab = useTerminalPanelStore((state) => state.createTab);
  const closeTab = useTerminalPanelStore((state) => state.closeTab);
  const closeAllTabs = useTerminalPanelStore((state) => state.closeAllTabs);
  const setActiveTab = useTerminalPanelStore((state) => state.setActiveTab);
  const renameTab = useTerminalPanelStore((state) => state.renameTab);
  const setTabSessionId = useTerminalPanelStore(
    (state) => state.setTabSessionId
  );
  const setTabStatus = useTerminalPanelStore((state) => state.setTabStatus);
  const [termHeight, setTermHeight] = useState(null);
  const [contextMenu, setContextMenu] = useState(null);
  const [debugAnalysis, setDebugAnalysis] = useState(null);
  const [debugLoading, setDebugLoading] = useState(false);
  const [showDebugPanel, setShowDebugPanel] = useState(false);
  const containerMapRef = useRef(/* @__PURE__ */ new Map());
  const terminalMapRef = useRef(/* @__PURE__ */ new Map());
  const fitMapRef = useRef(/* @__PURE__ */ new Map());
  const readerMapRef = useRef(
    /* @__PURE__ */ new Map()
  );
  const connectedRef = useRef(/* @__PURE__ */ new Set());
  const activeTab = useMemo(
    function activeTabMemo() {
      return tabs.find((tab) => tab.id === activeTabId) ?? tabs[0] ?? null;
    },
    [activeTabId, tabs]
  );
  const sendInput = useCallback(function sendInput2(tabId, data) {
    const currentTab = useTerminalPanelStore.getState().tabs.find((t) => t.id === tabId);
    if (!currentTab?.sessionId) return;
    fetch("/api/terminal-input", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sessionId: currentTab.sessionId, data })
    }).catch(function ignore() {
      return void 0;
    });
  }, []);
  const resizeSession = useCallback(async function resizeSession2(tabId, terminal) {
    const currentTab = useTerminalPanelStore.getState().tabs.find((t) => t.id === tabId);
    if (!currentTab?.sessionId) return;
    await fetch("/api/terminal-resize", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        sessionId: currentTab.sessionId,
        cols: terminal.cols,
        rows: terminal.rows
      })
    }).catch(function ignore() {
      return void 0;
    });
  }, []);
  const captureRecentTerminalOutput = useCallback(
    function captureRecentTerminalOutput2(tabId) {
      const terminal = terminalMapRef.current.get(tabId);
      if (!terminal) return "";
      const buffer = terminal.buffer.active;
      const startLine = Math.max(0, buffer.length - 100);
      const recentLines = [];
      for (let index = startLine; index < buffer.length; index += 1) {
        const line = buffer.getLine(index);
        if (!line) continue;
        recentLines.push(line.translateToString(true));
      }
      return recentLines.join("\n").trim();
    },
    []
  );
  const handleAnalyzeDebug = useCallback(
    async function handleAnalyzeDebug2() {
      if (!activeTab) return;
      setShowDebugPanel(true);
      setDebugLoading(true);
      setDebugAnalysis(null);
      try {
        const terminalOutput = captureRecentTerminalOutput(activeTab.id);
        const response = await fetch("/api/debug-analyze", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ terminalOutput })
        });
        const payload = await response.json().catch(function fallback() {
          return null;
        });
        const analysis = toDebugAnalysis(payload);
        if (!analysis) {
          throw new Error("Invalid analysis response payload");
        }
        setDebugAnalysis(analysis);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        setDebugAnalysis({
          summary: "Debug analysis failed.",
          rootCause: message,
          suggestedCommands: []
        });
      } finally {
        setDebugLoading(false);
      }
    },
    [activeTab, captureRecentTerminalOutput]
  );
  const handleRunDebugCommand = useCallback(
    function handleRunDebugCommand2(command) {
      if (!activeTab) return;
      void sendInput(activeTab.id, `${command}\r`);
    },
    [activeTab, sendInput]
  );
  const handleCloseDebugPanel = useCallback(function handleCloseDebugPanel2() {
    setShowDebugPanel(false);
  }, []);
  const focusActiveTerminal = useCallback(
    function focusActiveTerminal2() {
      if (!activeTab) return;
      const terminal = terminalMapRef.current.get(activeTab.id);
      terminal?.focus();
    },
    [activeTab]
  );
  const closeTabResources = useCallback(async function closeTabResources2(tabId, sessionId) {
    const reader = readerMapRef.current.get(tabId);
    readerMapRef.current.delete(tabId);
    if (reader) {
      await reader.cancel().catch(function ignore() {
        return void 0;
      });
    }
    const terminal = terminalMapRef.current.get(tabId);
    terminal?.dispose();
    terminalMapRef.current.delete(tabId);
    fitMapRef.current.delete(tabId);
    containerMapRef.current.delete(tabId);
    connectedRef.current.delete(tabId);
    if (sessionId) {
      await fetch("/api/terminal-close", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ sessionId })
      }).catch(function ignore() {
        return void 0;
      });
    }
  }, []);
  const handleCloseTab = useCallback(
    function handleCloseTab2(tab) {
      void closeTabResources(tab.id, tab.sessionId);
      closeTab(tab.id);
    },
    [closeTab, closeTabResources]
  );
  const handleClosePanel = useCallback(
    function handleClosePanel2() {
      const currentTabs = useTerminalPanelStore.getState().tabs;
      for (const tab of currentTabs) {
        void closeTabResources(tab.id, tab.sessionId);
      }
      closeAllTabs();
      setShowDebugPanel(false);
      if (onClosePanel) onClosePanel();
    },
    [closeAllTabs, closeTabResources, onClosePanel]
  );
  const connectTab = useCallback(
    async function connectTab2(tab) {
      if (connectedRef.current.has(tab.id)) return;
      const terminal = terminalMapRef.current.get(tab.id);
      if (!terminal) return;
      connectedRef.current.add(tab.id);
      setTabStatus(tab.id, "active");
      const response = await fetch("/api/terminal-stream", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          cwd: DEFAULT_TERMINAL_CWD,
          // Let the server pick the shell from $SHELL
          cols: terminal.cols,
          rows: terminal.rows,
          // If this tab already has a sessionId, ask the server to reattach
          // to that PTY rather than spawning a fresh one. Lets us survive
          // transient SSE disconnects (network blip, browser suspension,
          // HMR reload) without dropping the user's shell. See #298.
          sessionId: tab.sessionId || void 0
        })
      }).catch(function handleError() {
        return null;
      });
      if (!response || !response.ok || !response.body) {
        terminal.writeln("\r\n[terminal] failed to connect\r\n");
        connectedRef.current.delete(tab.id);
        setTabStatus(tab.id, "idle");
        return;
      }
      const reader = response.body.getReader();
      readerMapRef.current.set(tab.id, reader);
      const decoder = new TextDecoder();
      let buffer = "";
      let writeBuf = "";
      let flushTimer = null;
      const FLUSH_MS = 80;
      const MAX_BUF = 8192;
      function flushWrites() {
        flushTimer = null;
        if (writeBuf && terminal) {
          const chunk = writeBuf;
          writeBuf = "";
          terminal.write(chunk);
        }
      }
      function queueWrite(data) {
        writeBuf += data;
        if (writeBuf.length > MAX_BUF) {
          writeBuf = writeBuf.slice(-MAX_BUF);
        }
        if (!flushTimer) flushTimer = setTimeout(flushWrites, FLUSH_MS);
      }
      while (true) {
        const readState = await reader.read().catch(function onReadError() {
          return { done: true, value: void 0 };
        });
        const value = readState.value;
        if (readState.done) break;
        if (!value) continue;
        buffer += decoder.decode(value, { stream: true });
        const blocks = buffer.split("\n\n");
        buffer = blocks.pop() ?? "";
        for (let _bi = 0; _bi < blocks.length; _bi++) {
          if (_bi > 0 && _bi % 10 === 0)
            await new Promise((r) => setTimeout(r, 0));
          const block = blocks[_bi];
          if (!block.trim()) continue;
          const lines = block.split("\n");
          let eventName = "";
          let eventData = "";
          for (const line of lines) {
            if (line.startsWith("event: ")) {
              eventName = line.slice(7).trim();
              continue;
            }
            if (line.startsWith("data: ")) {
              eventData += line.slice(6);
              continue;
            }
            if (line.startsWith("data:")) {
              eventData += line.slice(5);
            }
          }
          if (!eventName || eventName === "ping") continue;
          if (eventName === "session" && eventData) {
            const payload = JSON.parse(eventData);
            if (payload.sessionId) {
              setTabSessionId(tab.id, payload.sessionId);
              const nextTitle = tab.cwd === "~" ? tab.title : tab.cwd;
              renameTab(tab.id, nextTitle);
            }
            continue;
          }
          if (eventName === "data" && eventData) {
            const payload = JSON.parse(eventData);
            if (typeof payload.data === "string") {
              queueWrite(payload.data);
            }
            continue;
          }
          if (eventName === "exit" && eventData) {
            const payload = JSON.parse(eventData);
            terminal.writeln(
              `\r
[process exited${payload.exitCode != null ? ` code=${payload.exitCode}` : ""}]\r
`
            );
            continue;
          }
          if (eventName === "error" && eventData) {
            terminal.writeln("\r\n[terminal] connection error\r\n");
          }
        }
      }
      if (flushTimer) clearTimeout(flushTimer);
      flushWrites();
      const latestTab = useTerminalPanelStore.getState().tabs.find((item) => item.id === tab.id);
      const previousSessionId = latestTab?.sessionId ?? null;
      connectedRef.current.delete(tab.id);
      setTabStatus(tab.id, "idle");
      if (previousSessionId) {
        const stillSameTab = useTerminalPanelStore.getState().tabs.find((item) => item.id === tab.id)?.sessionId === previousSessionId;
        if (stillSameTab) {
          terminal.writeln("\r\n\x1B[2m[reconnecting...]\x1B[0m");
          setTimeout(() => {
            const refreshed = useTerminalPanelStore.getState().tabs.find((item) => item.id === tab.id);
            if (refreshed && refreshed.sessionId === previousSessionId) {
              void connectTab2(refreshed);
            }
          }, 600);
          return;
        }
      }
      setTabSessionId(tab.id, null);
    },
    [renameTab, setTabSessionId, setTabStatus]
  );
  const ensureTerminalForTab = useCallback(
    function ensureTerminalForTab2(tab) {
      if (terminalMapRef.current.has(tab.id)) return;
      const container = containerMapRef.current.get(tab.id);
      if (!container) return;
      if (!xtermLoaded) {
        void ensureXterm().then(() => {
          if (!terminalMapRef.current.has(tab.id) && containerMapRef.current.has(tab.id)) {
            ensureTerminalForTab2(tab);
          }
        });
        return;
      }
      const isMobile = window.matchMedia("(max-width: 767px)").matches;
      const terminal = new TerminalCtor({
        cursorBlink: true,
        fontSize: isMobile ? 11 : 13,
        fontFamily: "JetBrains Mono, Menlo, Monaco, Consolas, monospace",
        theme: {
          background: TERMINAL_BG,
          foreground: "#e6e6e6",
          cursor: "#ea580c",
          selectionBackground: "#2b2b2b"
        }
      });
      const fitAddon = new FitAddonCtor();
      const webLinks = new WebLinksAddonCtor();
      terminal.loadAddon(fitAddon);
      terminal.loadAddon(webLinks);
      terminal.open(container);
      fitAddon.fit();
      terminal.onData(function onData(data) {
        void sendInput(tab.id, data);
      });
      terminalMapRef.current.set(tab.id, terminal);
      fitMapRef.current.set(tab.id, fitAddon);
      void resizeSession(tab.id, terminal);
      void connectTab(tab);
    },
    [connectTab, resizeSession, sendInput]
  );
  const handleCreateTab = useCallback(
    function handleCreateTab2() {
      const newTabId = createTab(DEFAULT_TERMINAL_CWD);
      window.setTimeout(function focusNewTab() {
        const tab = useTerminalPanelStore.getState().tabs.find((item) => item.id === newTabId);
        if (!tab) return;
        ensureTerminalForTab(tab);
        focusActiveTerminal();
      }, 0);
    },
    [createTab, ensureTerminalForTab, focusActiveTerminal]
  );
  useEffect(
    function closeContextMenuOnClick() {
      if (!contextMenu) return;
      function handlePointerDown() {
        setContextMenu(null);
      }
      function handleEscape(event) {
        if (event.key === "Escape") {
          setContextMenu(null);
        }
      }
      window.addEventListener("pointerdown", handlePointerDown);
      window.addEventListener("keydown", handleEscape);
      return function cleanup() {
        window.removeEventListener("pointerdown", handlePointerDown);
        window.removeEventListener("keydown", handleEscape);
      };
    },
    [contextMenu]
  );
  useEffect(
    function ensureTabsInitialized() {
      if (tabs.length === 0) {
        createTab(DEFAULT_TERMINAL_CWD);
        return;
      }
      if (!activeTabId) {
        setActiveTab(tabs[0].id);
      }
    },
    [activeTabId, createTab, setActiveTab, tabs]
  );
  useEffect(
    function initializeVisibleTabs() {
      for (const tab of tabs) {
        ensureTerminalForTab(tab);
      }
    },
    [ensureTerminalForTab, tabs]
  );
  useEffect(
    function focusAndFitOnVisible() {
      if (!panelVisible) return;
      window.setTimeout(() => {
        for (const fitAddon of fitMapRef.current.values()) {
          try {
            fitAddon.fit();
          } catch {
          }
        }
        const snapshot = useTerminalPanelStore.getState().tabs;
        for (const tab of snapshot) {
          const term = terminalMapRef.current.get(tab.id);
          if (term) void resizeSession(tab.id, term);
        }
        focusActiveTerminal();
      }, 100);
    },
    [focusActiveTerminal, panelVisible, resizeSession]
  );
  useEffect(
    function fitOnResize() {
      function refitAll() {
        for (const fitAddon of fitMapRef.current.values()) {
          try {
            fitAddon.fit();
          } catch {
          }
        }
        const snapshot = useTerminalPanelStore.getState().tabs;
        for (const tab of snapshot) {
          const terminal = terminalMapRef.current.get(tab.id);
          if (!terminal) continue;
          void resizeSession(tab.id, terminal);
        }
      }
      function handleResize() {
        const vv = window.visualViewport;
        if (vv) {
          setTermHeight(vv.height);
        }
        refitAll();
      }
      const timeout = window.setTimeout(handleResize, 50);
      window.addEventListener("resize", handleResize);
      window.visualViewport?.addEventListener("resize", handleResize);
      window.visualViewport?.addEventListener("scroll", handleResize);
      return function cleanup() {
        window.clearTimeout(timeout);
        window.removeEventListener("resize", handleResize);
        window.visualViewport?.removeEventListener("resize", handleResize);
        window.visualViewport?.removeEventListener("scroll", handleResize);
      };
    },
    [resizeSession]
  );
  useEffect(function disposeOnUnmount() {
    return function cleanup() {
      for (const reader of readerMapRef.current.values()) {
        void reader.cancel().catch(function ignore() {
          return void 0;
        });
      }
      readerMapRef.current.clear();
      for (const terminal of terminalMapRef.current.values()) {
        terminal.dispose();
      }
      terminalMapRef.current.clear();
      fitMapRef.current.clear();
      containerMapRef.current.clear();
      connectedRef.current.clear();
    };
  }, []);
  return /* @__PURE__ */ jsxs(
    "div",
    {
      className: "relative flex min-h-0 flex-col bg-primary-50",
      style: termHeight ? { height: termHeight, maxHeight: termHeight } : { height: "100%" },
      children: [
        /* @__PURE__ */ jsxs("div", { className: "flex h-8 items-center border-b border-primary-300 bg-primary-100 px-1", children: [
          /* @__PURE__ */ jsx("div", { className: "flex min-w-0 flex-1 items-center overflow-x-auto", children: tabs.map(function renderTab(tab) {
            const isActive = tab.id === activeTab?.id;
            return /* @__PURE__ */ jsxs(
              "button",
              {
                type: "button",
                onClick: function onClick() {
                  setActiveTab(tab.id);
                  window.setTimeout(function focusCurrent() {
                    terminalMapRef.current.get(tab.id)?.focus();
                  }, 0);
                },
                onContextMenu: function onContextMenu(event) {
                  event.preventDefault();
                  setContextMenu({
                    tabId: tab.id,
                    x: event.clientX,
                    y: event.clientY
                  });
                },
                className: cn(
                  "group relative flex h-8 max-w-[220px] items-center gap-2 px-3 text-xs text-primary-700 transition-colors",
                  isActive ? "bg-primary-50 text-primary-900" : "hover:bg-primary-200/70"
                ),
                children: [
                  /* @__PURE__ */ jsx(
                    "span",
                    {
                      className: cn(
                        "size-2 rounded-full",
                        isActive || tab.status === "active" ? "bg-emerald-400" : "bg-primary-500"
                      )
                    }
                  ),
                  /* @__PURE__ */ jsx(
                    HugeiconsIcon,
                    {
                      icon: ComputerTerminal01Icon,
                      size: 20,
                      strokeWidth: 1.5,
                      className: "shrink-0"
                    }
                  ),
                  /* @__PURE__ */ jsx("span", { className: "truncate text-left tabular-nums", children: tab.title }),
                  tabs.length > 1 ? /* @__PURE__ */ jsx(
                    "span",
                    {
                      role: "button",
                      tabIndex: 0,
                      onClick: function onClose(event) {
                        event.stopPropagation();
                        handleCloseTab(tab);
                      },
                      onKeyDown: function onCloseByKeyboard(event) {
                        if (event.key === "Enter" || event.key === " ") {
                          event.preventDefault();
                          handleCloseTab(tab);
                        }
                      },
                      className: "hidden rounded p-0.5 text-primary-600 hover:bg-primary-300 hover:text-primary-900 group-hover:inline-flex",
                      children: /* @__PURE__ */ jsx(
                        HugeiconsIcon,
                        {
                          icon: Cancel01Icon,
                          size: 20,
                          strokeWidth: 1.5
                        }
                      )
                    }
                  ) : null,
                  /* @__PURE__ */ jsx(
                    "span",
                    {
                      className: cn(
                        "pointer-events-none absolute inset-x-2 bottom-0 h-0.5 rounded-full bg-[#ea580c] transition-opacity",
                        isActive ? "opacity-100" : "opacity-0"
                      )
                    }
                  )
                ]
              },
              tab.id
            );
          }) }),
          /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-0.5", children: [
            /* @__PURE__ */ jsx(
              Button,
              {
                size: "icon-sm",
                variant: "ghost",
                onClick: handleAnalyzeDebug,
                disabled: debugLoading,
                "aria-label": "AI Debug analysis",
                title: "AI Debug — analyze terminal output",
                children: "🔍"
              }
            ),
            /* @__PURE__ */ jsx(
              Button,
              {
                size: "icon-sm",
                variant: "ghost",
                onClick: handleCreateTab,
                "aria-label": "New terminal tab",
                title: "New tab",
                children: /* @__PURE__ */ jsx(HugeiconsIcon, { icon: Add01Icon, size: 20, strokeWidth: 1.5 })
              }
            ),
            mode === "panel" ? /* @__PURE__ */ jsxs(Fragment, { children: [
              /* @__PURE__ */ jsx(
                Button,
                {
                  size: "icon-sm",
                  variant: "ghost",
                  onClick: onMinimizePanel,
                  "aria-label": "Minimize",
                  children: /* @__PURE__ */ jsx(
                    HugeiconsIcon,
                    {
                      icon: SidebarLeft01Icon,
                      size: 20,
                      strokeWidth: 1.5
                    }
                  )
                }
              ),
              /* @__PURE__ */ jsx(
                Button,
                {
                  size: "icon-sm",
                  variant: "ghost",
                  onClick: onMaximizePanel,
                  "aria-label": "Maximize",
                  children: /* @__PURE__ */ jsx(
                    HugeiconsIcon,
                    {
                      icon: ArrowRight01Icon,
                      size: 20,
                      strokeWidth: 1.5
                    }
                  )
                }
              ),
              /* @__PURE__ */ jsx(
                Button,
                {
                  size: "icon-sm",
                  variant: "ghost",
                  onClick: handleClosePanel,
                  "aria-label": "Close",
                  children: /* @__PURE__ */ jsx(
                    HugeiconsIcon,
                    {
                      icon: Cancel01Icon,
                      size: 20,
                      strokeWidth: 1.5
                    }
                  )
                }
              )
            ] }) : null
          ] })
        ] }),
        /* @__PURE__ */ jsx(
          "div",
          {
            className: "relative flex-1 overflow-hidden bg-primary-50",
            style: { backgroundColor: TERMINAL_BG },
            children: tabs.map(function renderTerminal(tab) {
              const isActive = tab.id === activeTab?.id;
              return /* @__PURE__ */ jsx(
                "div",
                {
                  className: cn("absolute inset-0", isActive ? "block" : "hidden"),
                  children: /* @__PURE__ */ jsx(
                    "div",
                    {
                      ref: function assignContainer(node) {
                        if (node) {
                          containerMapRef.current.set(tab.id, node);
                          ensureTerminalForTab(tab);
                          return;
                        }
                        containerMapRef.current.delete(tab.id);
                      },
                      onClick: function tapToFocus() {
                        terminalMapRef.current.get(tab.id)?.focus();
                      },
                      className: "h-full w-full bg-primary-50 font-mono text-primary-900",
                      style: { backgroundColor: TERMINAL_BG }
                    }
                  )
                },
                tab.id
              );
            })
          }
        ),
        showDebugPanel ? /* @__PURE__ */ jsx(
          DebugPanel,
          {
            analysis: debugAnalysis,
            isLoading: debugLoading,
            onRunCommand: handleRunDebugCommand,
            onClose: handleCloseDebugPanel
          }
        ) : null,
        contextMenu ? /* @__PURE__ */ jsxs(
          "div",
          {
            className: "fixed z-50 min-w-36 rounded-md border border-primary-300 bg-primary-100 p-1 shadow-lg",
            style: { top: contextMenu.y, left: contextMenu.x },
            onClick: function stop(event) {
              event.stopPropagation();
            },
            children: [
              /* @__PURE__ */ jsx(
                "button",
                {
                  type: "button",
                  className: "flex w-full items-center rounded px-2 py-1.5 text-left text-xs text-primary-900 hover:bg-primary-200",
                  onClick: function renameTabFromMenu() {
                    const menuTab = tabs.find((tab) => tab.id === contextMenu.tabId);
                    setContextMenu(null);
                    if (!menuTab) return;
                    const nextName = window.prompt(
                      "Rename terminal tab",
                      menuTab.title
                    );
                    if (!nextName) return;
                    renameTab(menuTab.id, nextName);
                  },
                  children: "Rename"
                }
              ),
              /* @__PURE__ */ jsx(
                "button",
                {
                  type: "button",
                  className: "flex w-full items-center rounded px-2 py-1.5 text-left text-xs text-primary-900 hover:bg-primary-200",
                  onClick: function closeTabFromMenu() {
                    const menuTab = tabs.find((tab) => tab.id === contextMenu.tabId);
                    setContextMenu(null);
                    if (!menuTab) return;
                    handleCloseTab(menuTab);
                  },
                  children: "Close"
                }
              )
            ]
          }
        ) : null
      ]
    }
  );
}
export {
  TerminalWorkspace
};
