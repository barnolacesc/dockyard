// Dockyard Mobile Companion — Client Application

(function() {
  const urlParams = new URLSearchParams(window.location.search);
  const rawToken = urlParams.get('token') || localStorage.getItem('dockyard_token') || '';
  let authToken = /^[a-zA-Z0-9_]{1,64}$/.test(rawToken) ? rawToken : '';

  if (urlParams.get('token') && authToken) {
    localStorage.setItem('dockyard_token', authToken);
    // Remove token from URL without reload
    const cleanUrl = window.location.pathname + (urlParams.get('standalone') ? '?standalone=true' : '');
    window.history.replaceState({}, document.title, cleanUrl);
  }

  // App State
  let state = {
    connected: false,
    projects: [],
    selectedWorkstreamId: null,
    terminalLines: '',
    autoScroll: true,
    isListeningVoice: false,
    speechRecognition: null
  };

  // DOM Elements
  const els = {
    connectionPill: document.getElementById('connection-pill'),
    connectionText: document.getElementById('connection-text'),
    currentWsName: document.getElementById('current-ws-name'),
    currentWsBranch: document.getElementById('current-ws-branch'),
    terminalMirror: document.getElementById('terminal-mirror'),
    scrollBottomBtn: document.getElementById('scroll-bottom-btn'),
    agentWaitingBanner: document.getElementById('agent-waiting-banner'),
    waitingText: document.getElementById('waiting-text'),
    btnApprove: document.getElementById('btn-approve'),
    btnDeny: document.getElementById('btn-deny'),
    promptInput: document.getElementById('prompt-input'),
    micBtn: document.getElementById('mic-btn'),
    sendBtn: document.getElementById('send-btn'),
    sidebarOverlay: document.getElementById('sidebar-overlay'),
    sidebarDrawer: document.getElementById('sidebar-drawer'),
    drawerContent: document.getElementById('drawer-content'),
    menuBtn: document.getElementById('menu-btn'),
    drawerCloseBtn: document.getElementById('drawer-close-btn')
  };

  // Initialize Speech Recognition if supported
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (SpeechRecognition) {
    const recognition = new SpeechRecognition();
    recognition.continuous = false;
    recognition.interimResults = true;
    recognition.lang = navigator.language || 'en-US';

    recognition.onresult = (event) => {
      let interimTranscript = '';
      for (let i = event.resultIndex; i < event.results.length; ++i) {
        if (event.results[i].isFinal) {
          els.promptInput.value += event.results[i][0].transcript;
        } else {
          interimTranscript += event.results[i][0].transcript;
        }
      }
    };

    recognition.onend = () => {
      state.isListeningVoice = false;
      els.micBtn.classList.remove('listening');
    };

    recognition.onerror = () => {
      state.isListeningVoice = false;
      els.micBtn.classList.remove('listening');
    };

    state.speechRecognition = recognition;
  } else {
    els.micBtn.style.display = 'none';
  }

  // UI Event Handlers
  els.menuBtn.addEventListener('click', openSidebar);
  els.drawerCloseBtn.addEventListener('click', closeSidebar);
  els.sidebarOverlay.addEventListener('click', closeSidebar);

  els.btnApprove.addEventListener('click', () => sendAction('approve'));
  els.btnDeny.addEventListener('click', () => sendAction('deny'));

  els.sendBtn.addEventListener('click', sendPrompt);
  els.promptInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      sendPrompt();
    }
  });

  els.micBtn.addEventListener('click', toggleVoiceDictation);

  document.querySelectorAll('.key-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const key = e.target.dataset.key;
      if (key === 'ctrl-c') {
        sendAction('interrupt');
      } else if (key === 'enter') {
        sendRawKey('\n');
      } else if (key === 'tab') {
        sendRawKey('\t');
      } else if (key === 'esc') {
        sendRawKey('\x1b');
      } else if (key === 'clear') {
        els.terminalMirror.replaceChildren();
      }
    });
  });

  els.terminalMirror.addEventListener('scroll', () => {
    const threshold = 40;
    const isAtBottom = els.terminalMirror.scrollHeight - els.terminalMirror.scrollTop - els.terminalMirror.clientHeight <= threshold;
    state.autoScroll = isAtBottom;
    if (isAtBottom) {
      els.scrollBottomBtn.classList.remove('visible');
    } else {
      els.scrollBottomBtn.classList.add('visible');
    }
  });

  els.scrollBottomBtn.addEventListener('click', () => {
    scrollToBottom();
    state.autoScroll = true;
    els.scrollBottomBtn.classList.remove('visible');
  });

  function openSidebar() {
    els.sidebarDrawer.classList.add('open');
    els.sidebarOverlay.classList.add('open');
  }

  function closeSidebar() {
    els.sidebarDrawer.classList.remove('open');
    els.sidebarOverlay.classList.remove('open');
  }

  function scrollToBottom() {
    els.terminalMirror.scrollTop = els.terminalMirror.scrollHeight;
  }

  function toggleVoiceDictation() {
    if (!state.speechRecognition) return;
    if (state.isListeningVoice) {
      state.speechRecognition.stop();
      state.isListeningVoice = false;
      els.micBtn.classList.remove('listening');
    } else {
      try {
        state.speechRecognition.start();
        state.isListeningVoice = true;
        els.micBtn.classList.add('listening');
      } catch (err) {
        console.error('Speech recognition error:', err);
      }
    }
  }

  // Strict Validation Helpers
  const UUID_REGEX = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
  const ALLOWED_ACTIONS = ['approve', 'deny', 'interrupt'];

  function validateWorkstreamId(id) {
    if (typeof id !== 'string' || !UUID_REGEX.test(id)) {
      throw new Error('Invalid workstream ID');
    }
    return id;
  }

  function validateAction(action) {
    if (!ALLOWED_ACTIONS.includes(action)) {
      throw new Error('Invalid action');
    }
    return action;
  }

  // Network Calls with strict endpoint validation
  async function apiFetch(endpoint, options = {}) {
    if (typeof endpoint !== 'string' || !endpoint.startsWith('/api/')) {
      throw new Error('Invalid API endpoint');
    }

    const url = new URL(endpoint, window.location.origin);
    if (url.origin !== window.location.origin) {
      throw new Error('Untrusted origin');
    }

    options.headers = options.headers || {};
    if (authToken) {
      options.headers['Authorization'] = `Bearer ${authToken}`;
    }
    options.credentials = 'same-origin';

    const res = await fetch(url, options);
    if (res.status === 401) {
      setConnectionStatus(false, 'Unauthorized');
      const newToken = prompt('Enter your Dockyard Mobile token:');
      if (newToken && /^[a-zA-Z0-9_]{1,64}$/.test(newToken.trim())) {
        authToken = newToken.trim();
        localStorage.setItem('dockyard_token', authToken);
        location.reload();
      }
      throw new Error('Unauthorized');
    }
    return res;
  }

  async function sendAction(action) {
    if (!state.selectedWorkstreamId) return;
    try {
      const wsId = validateWorkstreamId(state.selectedWorkstreamId);
      const safeAction = validateAction(action);
      await apiFetch(`/api/workstreams/${wsId}/${safeAction}`, {
        method: 'POST'
      });
      // Refresh terminal after short delay
      setTimeout(fetchCurrentTerminal, 300);
    } catch (err) {
      console.error(`Failed to send ${action}:`, err);
    }
  }

  async function sendRawKey(key) {
    if (!state.selectedWorkstreamId) return;
    try {
      const wsId = validateWorkstreamId(state.selectedWorkstreamId);
      await apiFetch(`/api/workstreams/${wsId}/input`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text: key, pressEnter: false })
      });
      setTimeout(fetchCurrentTerminal, 250);
    } catch (err) {
      console.error('Failed to send key:', err);
    }
  }

  async function sendPrompt() {
    const text = els.promptInput.value.trim();
    if (!text || !state.selectedWorkstreamId) return;
    els.promptInput.value = '';
    try {
      const wsId = validateWorkstreamId(state.selectedWorkstreamId);
      await apiFetch(`/api/workstreams/${wsId}/input`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text: text, pressEnter: true })
      });
      setTimeout(fetchCurrentTerminal, 350);
    } catch (err) {
      console.error('Failed to send prompt:', err);
    }
  }

  async function fetchInitialStatus() {
    try {
      const res = await apiFetch('/api/status');
      const data = await res.json();
      state.projects = data.projects || [];
      renderSidebar();

      // Pick first workstream if none selected
      if (!state.selectedWorkstreamId) {
        for (const proj of state.projects) {
          if (proj.workstreams && proj.workstreams.length > 0) {
            selectWorkstream(proj.workstreams[0].id);
            break;
          }
        }
      } else {
        updateCurrentWorkstreamHeader();
      }
      setConnectionStatus(true, data.host?.name || 'Connected');
    } catch (err) {
      console.error('Failed to fetch status:', err);
      setConnectionStatus(false, 'Disconnected');
    }
  }

  async function fetchCurrentTerminal() {
    if (!state.selectedWorkstreamId) return;
    try {
      const wsId = validateWorkstreamId(state.selectedWorkstreamId);
      const res = await apiFetch(`/api/workstreams/${wsId}/terminal?lines=150`);
      if (res.ok) {
        const text = await res.text();
        renderTerminal(text);
      }
    } catch (err) {
      console.error('Failed to fetch terminal:', err);
    }
  }

  function setConnectionStatus(connected, text) {
    state.connected = connected;
    if (connected) {
      els.connectionPill.classList.add('connected');
    } else {
      els.connectionPill.classList.remove('connected');
    }
    els.connectionText.textContent = text;
  }

  function selectWorkstream(id) {
    if (!id || typeof id !== 'string' || !/^[0-9a-fA-F-]{1,64}$/.test(id)) return;
    const found = findWorkstream(id);
    if (!found) return;
    state.selectedWorkstreamId = found.workstream.id;
    closeSidebar();
    updateCurrentWorkstreamHeader();
    renderSidebar();
    fetchCurrentTerminal();
  }

  function findWorkstream(id) {
    for (const p of state.projects) {
      for (const w of (p.workstreams || [])) {
        if (w.id === id) return { project: p, workstream: w };
      }
    }
    return null;
  }

  function updateCurrentWorkstreamHeader() {
    const found = findWorkstream(state.selectedWorkstreamId);
    if (found) {
      els.currentWsName.textContent = found.workstream.name;
      els.currentWsBranch.textContent = found.workstream.branch || found.project.name;

      if (found.workstream.agentState === 'waiting') {
        els.agentWaitingBanner.style.display = 'flex';
        els.waitingText.textContent = 'Agent is waiting for input or approval';
      } else {
        els.agentWaitingBanner.style.display = 'none';
      }
    } else {
      els.currentWsName.textContent = 'Dockyard';
      els.currentWsBranch.textContent = 'No workstream selected';
      els.agentWaitingBanner.style.display = 'none';
    }
  }

  function renderSidebar() {
    els.drawerContent.replaceChildren();

    if (!state.projects || state.projects.length === 0) {
      const emptyMsg = document.createElement('div');
      emptyMsg.className = 'empty-projects-msg';
      emptyMsg.textContent = 'No active projects found';
      els.drawerContent.appendChild(emptyMsg);
      return;
    }

    for (const proj of state.projects) {
      const groupEl = document.createElement('div');
      groupEl.className = 'project-group';

      const titleEl = document.createElement('div');
      titleEl.className = 'project-title';
      titleEl.textContent = proj.name || 'Untitled';
      groupEl.appendChild(titleEl);

      for (const ws of (proj.workstreams || [])) {
        const isSelected = ws.id === state.selectedWorkstreamId;
        const stateClass = ws.agentState || 'idle';
        let stateLabel = stateClass.toUpperCase();
        if (ws.agentState === 'working') stateLabel = 'WORKING';
        if (ws.agentState === 'waiting') stateLabel = 'WAITING';

        const card = document.createElement('div');
        card.className = `workstream-card ${isSelected ? 'selected' : ''}`;
        card.dataset.id = ws.id;

        const rowTop = document.createElement('div');
        rowTop.className = 'ws-row-top';

        const nameSpan = document.createElement('span');
        nameSpan.className = 'ws-name';
        nameSpan.textContent = ws.name || 'Unnamed';

        const badge = document.createElement('span');
        badge.className = `ws-badge ${stateClass}`;

        const dot = document.createElement('span');
        dot.className = 'dot';
        badge.appendChild(dot);
        badge.appendChild(document.createTextNode(' ' + stateLabel));

        rowTop.appendChild(nameSpan);
        rowTop.appendChild(badge);
        card.appendChild(rowTop);

        const branchEl = document.createElement('div');
        branchEl.className = 'ws-branch';
        branchEl.textContent = ws.branch || '';
        card.appendChild(branchEl);

        const tagsEl = document.createElement('div');
        tagsEl.className = 'ws-tags';

        if (ws.activeSubagents > 0) {
          const subtag = document.createElement('span');
          subtag.className = 'ws-tag';
          subtag.textContent = `${ws.activeSubagents} Subagent${ws.activeSubagents > 1 ? 's' : ''}`;
          tagsEl.appendChild(subtag);
        }

        if (Array.isArray(ws.listeningPorts)) {
          for (const port of ws.listeningPorts) {
            const portNum = parseInt(port, 10);
            if (portNum > 0 && portNum <= 65535) {
              const portLink = document.createElement('a');
              portLink.className = 'ws-tag port';
              portLink.target = '_blank';
              portLink.rel = 'noopener noreferrer';
              portLink.textContent = `Port ${portNum} ↗`;
              portLink.href = `http://${window.location.hostname}:${portNum}`;
              portLink.addEventListener('click', (e) => e.stopPropagation());
              tagsEl.appendChild(portLink);
            }
          }
        }

        card.appendChild(tagsEl);

        card.addEventListener('click', () => {
          selectWorkstream(ws.id);
        });

        groupEl.appendChild(card);
      }

      els.drawerContent.appendChild(groupEl);
    }
  }

  // Raw ANSI to HTML Parser
  function ansiToHtml(str) {
    if (!str) return '';

    // Strip carriage returns and non-color terminal controls (like cursor position/hide)
    str = str.replace(/\x1b\[\?25[hl]/g, ''); // cursor show/hide
    str = str.replace(/\x1b\[[0-9;]*[HfABCDsuJK]/g, ''); // cursor movement & clear line

    const codeToClass = {
      1: 'ansi-bold',
      2: 'ansi-dim',
      3: 'ansi-italic',
      4: 'ansi-underline',
      30: 'ansi-black',
      31: 'ansi-red',
      32: 'ansi-green',
      33: 'ansi-yellow',
      34: 'ansi-blue',
      35: 'ansi-magenta',
      36: 'ansi-cyan',
      37: 'ansi-white',
      40: 'ansi-bg-black',
      41: 'ansi-bg-red',
      42: 'ansi-bg-green',
      43: 'ansi-bg-yellow',
      44: 'ansi-bg-blue',
      45: 'ansi-bg-magenta',
      46: 'ansi-bg-cyan',
      47: 'ansi-bg-white'
    };

    let result = '';
    let currentClasses = new Set();
    const tokens = str.split(/(\x1b\[[0-9;]*m)/g);

    for (const token of tokens) {
      if (token.startsWith('\x1b[')) {
        const rawCodes = token.slice(2, -1).split(';').map(n => parseInt(n, 10) || 0);
        for (const code of rawCodes) {
          if (code === 0) {
            currentClasses.clear();
          } else if (codeToClass[code]) {
            currentClasses.add(codeToClass[code]);
          }
        }
      } else if (token) {
        if (currentClasses.size > 0) {
          result += `<span class="${Array.from(currentClasses).join(' ')}">${escapeHtml(token)}</span>`;
        } else {
          result += escapeHtml(token);
        }
      }
    }

    return result;
  }

  function renderTerminal(text) {
    els.terminalMirror.innerHTML = ansiToHtml(text);
    if (state.autoScroll) {
      scrollToBottom();
    }
  }

  function escapeHtml(str) {
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  // WebSocket Connection
  function setupWebSocket() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}/ws?token=${encodeURIComponent(authToken)}`;

    let ws = null;
    try {
      ws = new WebSocket(wsUrl);
    } catch (e) {
      setTimeout(setupWebSocket, 3000);
      return;
    }

    ws.onopen = () => {
      setConnectionStatus(true, 'Live');
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.type === 'snapshot') {
          state.projects = msg.projects || [];
          renderSidebar();
          updateCurrentWorkstreamHeader();
        } else if (msg.type === 'state_change') {
          for (const proj of state.projects) {
            for (const ws of (proj.workstreams || [])) {
              if (ws.id === msg.workstreamId) {
                ws.agentState = msg.state;
                if (msg.subagents !== undefined) ws.activeSubagents = msg.subagents;
              }
            }
          }
          renderSidebar();
          updateCurrentWorkstreamHeader();
        } else if (msg.type === 'terminal_chunk') {
          if (msg.workstreamId === state.selectedWorkstreamId && msg.text) {
            renderTerminal(msg.text);
          }
        }
      } catch (err) {
        console.error('Error handling WebSocket message:', err);
      }
    };

    ws.onclose = () => {
      setConnectionStatus(false, 'Reconnecting...');
      setTimeout(setupWebSocket, 3000);
    };

    ws.onerror = () => {
      ws.close();
    };
  }

  // Polling fallback to keep terminal fresh even without WebSocket updates
  setInterval(() => {
    if (document.visibilityState === 'visible' && state.selectedWorkstreamId) {
      fetchCurrentTerminal();
    }
  }, 2500);

  // Initial load
  fetchInitialStatus().then(() => {
    setupWebSocket();
    fetchCurrentTerminal();
  });
})();
